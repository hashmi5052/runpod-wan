import runpod
from runpod.serverless.utils import rp_upload
import json
import urllib.request
import urllib.parse
import time
import os
import requests
import base64
from io import BytesIO
import websocket
import uuid
import tempfile
import socket
import traceback
from mutagen.mp4 import MP4
import subprocess
import shutil
import threading

# Configuration (same as original)
COMFY_API_AVAILABLE_INTERVAL_MS = 1000
COMFY_API_AVAILABLE_MAX_RETRIES = 300
WEBSOCKET_RECONNECT_ATTEMPTS = int(os.environ.get("WEBSOCKET_RECONNECT_ATTEMPTS", 100))
WEBSOCKET_RECONNECT_DELAY_S = int(os.environ.get("WEBSOCKET_RECONNECT_DELAY_S", 3))
WEBSOCKET_RECEIVE_TIMEOUT = int(os.environ.get("WEBSOCKET_RECEIVE_TIMEOUT", 30))
MAX_EXECUTION_TIME = int(os.environ.get("MAX_EXECUTION_TIME", 1200))
CALLBACK_API_ENDPOINT = os.environ.get("CALLBACK_API_ENDPOINT", "")
CALLBACK_API_SECRET = os.environ.get("CALLBACK_API_SECRET", "")
if os.environ.get("WEBSOCKET_TRACE", "false").lower() == "true":
    websocket.enableTrace(True)
COMFY_HOST = os.environ.get("COMFY_HOST", "127.0.0.1:3000")
COMFY_BASE_DIR = os.environ.get("COMFY_BASE_DIR", "/workspace/ComfyUI")
COMFY_MAIN_PY = os.path.join(COMFY_BASE_DIR, "main.py")
REFRESH_WORKER = os.environ.get("REFRESH_WORKER", "false").lower() == "true"

# Helper funcs copied and trimmed from original file

def _comfy_server_status():
    try:
        resp = requests.get(f"http://{COMFY_HOST}/", timeout=5)
        return {"reachable": resp.status_code == 200, "status_code": resp.status_code}
    except Exception as exc:
        return {"reachable": False, "error": str(exc)}


def start_comfyui(background=True, wait_until_ready=True, timeout_s=120):
    try:
        status = _comfy_server_status()
        if status.get("reachable"):
            print("worker-comfyui - ComfyUI already running.")
            return True
    except Exception:
        pass

    if not os.path.exists(COMFY_MAIN_PY):
        print(f"worker-comfyui - ComfyUI main.py not found at {COMFY_MAIN_PY}. Aborting start.")
        return False

    use_cpu = False
    if shutil.which("nvidia-smi") is None:
        print("worker-comfyui - No NVIDIA GPU detected. Starting ComfyUI in CPU mode.")
        use_cpu = True
    else:
        print("worker-comfyui - NVIDIA GPU detected. Starting ComfyUI with GPU support if available.")

    cmd = ["python", COMFY_MAIN_PY, "--listen", "0.0.0.0", "--port", COMFY_HOST.split(":")[-1]]
    if use_cpu:
        cmd += ["--use-cpu", "all", "--no-half", "--precision", "full"]

    stdout_log = os.path.join(COMFY_BASE_DIR, "comfyui_stdout.log")
    stderr_log = os.path.join(COMFY_BASE_DIR, "comfyui_stderr.log")

    try:
        out_fd = open(stdout_log, "ab")
        err_fd = open(stderr_log, "ab")
        subprocess.Popen(cmd, cwd=COMFY_BASE_DIR, stdout=out_fd, stderr=err_fd, start_new_session=True, close_fds=True)
    except Exception as e:
        print(f"worker-comfyui - Failed to start ComfyUI process: {e}")
        return False

    if not wait_until_ready:
        return True

    start = time.time()
    while time.time() - start < timeout_s:
        st = _comfy_server_status()
        if st.get("reachable"):
            print("worker-comfyui - ComfyUI is ready.")
            return True
        time.sleep(2)
    print("worker-comfyui - Timeout waiting for ComfyUI to become ready.")
    return False


def callback_api(payload):
    if CALLBACK_API_ENDPOINT != "":
        try:
            headers = {"X-API-Key": f"{CALLBACK_API_SECRET}"}
            response = requests.post(CALLBACK_API_ENDPOINT, json=payload, headers=headers, timeout=30)
            if response.status_code != 200:
                print(f"worker-comfyui - Failed to send log to API. Status code: {response.status_code}")
        except Exception as e:
            print(f"worker-comfyui - Error during callback: {e}")


def validate_input(job_input):
    if job_input is None:
        return None, "Please provide input"
    if isinstance(job_input, str):
        try:
            job_input = json.loads(job_input)
        except json.JSONDecodeError:
            return None, "Invalid JSON format in input"
    workflow = job_input.get("workflow")
    if workflow is None:
        return None, "Missing 'workflow' parameter"
    images = job_input.get("images")
    if images is not None:
        if not isinstance(images, list) or not all("name" in image and "image" in image for image in images):
            return None, "'images' must be a list of objects with 'name' and 'image' keys"
    return {"workflow": workflow, "images": images}, None


def upload_images(images):
    if not images:
        return {"status": "success", "message": "No images to upload", "details": []}
    responses = []
    upload_errors = []
    print(f"worker-comfyui - Uploading {len(images)} image(s)...")
    for image in images:
        try:
            name = image["name"]
            image_data_uri = image["image"]
            if "," in image_data_uri:
                base64_data = image_data_uri.split(",", 1)[1]
            else:
                base64_data = image_data_uri
            blob = base64.b64decode(base64_data)
            files = {"image": (name, BytesIO(blob), "image/png"), "overwrite": (None, "true")}
            response = requests.post(f"http://{COMFY_HOST}/upload/image", files=files, timeout=30)
            response.raise_for_status()
            responses.append(f"Successfully uploaded {name}")
            print(f"worker-comfyui - Successfully uploaded {name}")
        except Exception as e:
            error_msg = f"Error uploading {image.get('name', 'unknown')}: {e}"
            print(f"worker-comfyui - {error_msg}")
            upload_errors.append(error_msg)
    if upload_errors:
        print(f"worker-comfyui - image(s) upload finished with errors")
        return {"status": "error", "message": "Some images failed to upload", "details": upload_errors}
    print(f"worker-comfyui - image(s) upload complete")
    return {"status": "success", "message": "All images uploaded successfully", "details": responses}


def queue_workflow(workflow, client_id):
    payload = {"prompt": workflow, "client_id": client_id}
    data = json.dumps(payload).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    response = requests.post(f"http://{COMFY_HOST}/prompt", data=data, headers=headers, timeout=30)
    if response.status_code == 400:
        print(f"worker-comfyui - ComfyUI returned 400. Response body: {response.text}")
        try:
            error_data = response.json()
            error_message = "Workflow validation failed"
            if "error" in error_data:
                error_info = error_data["error"]
                if isinstance(error_info, dict):
                    error_message = error_info.get("message", error_message)
                else:
                    error_message = str(error_info)
            raise ValueError(f"{error_message}. Raw response: {response.text}")
        except (json.JSONDecodeError, KeyError):
            raise ValueError(f"ComfyUI validation failed (could not parse error response): {response.text}")
    response.raise_for_status()
    return response.json()


def get_history(prompt_id):
    response = requests.get(f"http://{COMFY_HOST}/history/{prompt_id}", timeout=30)
    response.raise_for_status()
    return response.json()


def file_handler(job_id, node_id, execution_time, file_info):
    filename = file_info.get("filename")
    subfolder = file_info.get("subfolder", "")
    img_type = file_info.get("type")
    if img_type == "temp":
        print(f"worker-comfyui - Skipping image {filename} because type is 'temp'")
        return None
    if not filename:
        print(f"worker-comfyui - Skipping image in node {node_id} due to missing filename: {file_info}")
        return None
    try:
        response = requests.get(f"http://{COMFY_HOST}/view?" + urllib.parse.urlencode({"filename": filename, "subfolder": subfolder, "type": img_type}), timeout=60)
        response.raise_for_status()
        image_bytes = response.content
    except Exception as e:
        print(f"worker-comfyui - Error fetching image data for {filename}: {e}")
        return None
    file_extension = os.path.splitext(filename)[1] or ".png"
    if os.environ.get("BUCKET_ENDPOINT_URL"):
        try:
            with tempfile.NamedTemporaryFile(suffix=file_extension, delete=False) as temp_file:
                temp_file.write(image_bytes)
                temp_file_path = temp_file.name
            if file_extension == ".mp4":
                try:
                    vid = MP4(temp_file_path)
                    if "©cmt" in vid.tags:
                        del vid.tags["©cmt"]
                        vid.save()
                except Exception:
                    pass
            s3_url = rp_upload.upload_image(job_id, temp_file_path)
            os.remove(temp_file_path)
            callback_api({"action": "s3_upload", "job_id": job_id, "filename": filename, "data": s3_url, "execution_time": execution_time})
            return {"filename": filename, "type": "s3_url", "data": s3_url}
        except Exception as e:
            print(f"worker-comfyui - Error uploading {filename} to S3: {e}")
            if "temp_file_path" in locals() and os.path.exists(temp_file_path):
                try:
                    os.remove(temp_file_path)
                except OSError:
                    pass
            return None
    else:
        try:
            base64_image = base64.b64encode(image_bytes).decode("utf-8")
            return {"filename": filename, "type": "base64", "data": base64_image}
        except Exception as e:
            print(f"worker-comfyui - Error encoding {filename} to base64: {e}")
            return None


# New background job processor. Runs independently of the handler return.

def process_job_background(job_id, workflow, images, client_id):
    """Background job that queues workflow and monitors it via websocket."""
    try:
        ws_url = f"ws://{COMFY_HOST}/ws?clientId={client_id}"
        print(f"[bg-{job_id}] Connecting to websocket: {ws_url}")
        ws = websocket.WebSocket()
        ws.settimeout(WEBSOCKET_RECEIVE_TIMEOUT)
        ws.connect(ws_url, timeout=10)
        print(f"[bg-{job_id}] Websocket connected")

        # Upload images if provided
        if images:
            up = upload_images(images)
            if up.get("status") == "error":
                callback_api({"action": "error", "job_id": job_id, "errors": up.get("details")})
                ws.close()
                return

        queued = queue_workflow(workflow, client_id)
        prompt_id = queued.get("prompt_id")
        if not prompt_id:
            raise ValueError(f"Missing prompt_id in queue response: {queued}")
        print(f"[bg-{job_id}] Queued workflow with ID: {prompt_id}")
        callback_api({"action": "in_queue", "job_id": job_id})

        start_time = time.time()
        last_progress_time = start_time
        execution_done = False
        errors = []

        while True:
            if time.time() - start_time > MAX_EXECUTION_TIME:
                raise TimeoutError(f"Job exceeded max execution time of {MAX_EXECUTION_TIME} seconds")
            try:
                out = ws.recv()
                last_progress_time = time.time()
                if isinstance(out, str):
                    message = json.loads(out)
                    mtype = message.get("type")
                    if mtype == "status":
                        status_data = message.get("data", {}).get("status", {})
                        queue_remaining = status_data.get('exec_info', {}).get('queue_remaining', 'N/A')
                        print(f"[bg-{job_id}] Status: {queue_remaining} items remaining")
                    elif mtype == "executing":
                        data = message.get("data", {})
                        if data.get("node") is None and data.get("prompt_id") == prompt_id:
                            print(f"[bg-{job_id}] Execution finished for prompt {prompt_id}")
                            execution_done = True
                            break
                        elif data.get("prompt_id") == prompt_id:
                            node_id = data.get("node")
                            if node_id:
                                print(f"[bg-{job_id}] Executing node: {node_id}")
                    elif mtype == "execution_error":
                        data = message.get("data", {})
                        if data.get("prompt_id") == prompt_id:
                            err = f"Node Type: {data.get('node_type')}, Node ID: {data.get('node_id')}, Message: {data.get('exception_message')}"
                            print(f"[bg-{job_id}] Execution error: {err}")
                            errors.append(err)
                            break
                    elif mtype == "progress":
                        data = message.get("data", {})
                        if data.get("prompt_id") == prompt_id:
                            value = data.get("value", 0)
                            max_val = data.get("max", 100)
                            node_id = data.get("node")
                            print(f"[bg-{job_id}] Progress: {value}/{max_val} (Node: {node_id})")
            except websocket.WebSocketTimeoutException:
                if time.time() - last_progress_time > 120:
                    srv_status = _comfy_server_status()
                    if not srv_status["reachable"]:
                        errors.append("ComfyUI became unreachable during execution")
                        break
                print(f"[bg-{job_id}] Websocket receive timed out. Still waiting...")
                continue
            except websocket.WebSocketConnectionClosedException as closed_err:
                try:
                    ws = _attempt_websocket_reconnect(ws_url, WEBSOCKET_RECONNECT_ATTEMPTS, WEBSOCKET_RECONNECT_DELAY_S, closed_err)
                    print(f"[bg-{job_id}] Reconnected websocket")
                    continue
                except websocket.WebSocketConnectionClosedException as reconn_failed_err:
                    errors.append(str(reconn_failed_err))
                    break
            except json.JSONDecodeError:
                print(f"[bg-{job_id}] Received invalid JSON message via websocket.")
                continue

        # Fetch history and handle outputs
        try:
            history = get_history(prompt_id)
            prompt_history = history.get(prompt_id, {})
            outputs = prompt_history.get("outputs", {})
            output_data = []
            execution_time = 0
            if outputs:
                for node_id, node_output in outputs.items():
                    if "images" in node_output:
                        for img_info in node_output["images"]:
                            f = file_handler(job_id, node_id, execution_time, img_info)
                            if f:
                                output_data.append(f)
                    if "gifs" in node_output:
                        for gif_info in node_output["gifs"]:
                            f = file_handler(job_id, node_id, execution_time, gif_info)
                            if f:
                                output_data.append(f)
            callback_api({"action": "complete", "job_id": job_id, "result": {"images": output_data, "errors": errors}})
            print(f"[bg-{job_id}] Background job finished. Uploaded {len(output_data)} files.")
        except Exception as e:
            print(f"[bg-{job_id}] Error fetching history or handling outputs: {e}")
            callback_api({"action": "error", "job_id": job_id, "errors": [str(e)]})
        finally:
            try:
                ws.close()
            except Exception:
                pass

    except Exception as e:
        print(f"[bg-{job_id}] Unexpected background error: {e}")
        traceback.print_exc()
        callback_api({"action": "error", "job_id": job_id, "errors": [str(e)]})


# Fast handler. Returns immediately with websocket info and schedules background processing.

def handler(job):
    # Ensure ComfyUI process is started but do not block waiting for full readiness
    _ = start_comfyui(background=True, wait_until_ready=False)

    job_input = job.get("input", {})
    job_id = job.get("id", str(uuid.uuid4()))
    validated_data, error_message = validate_input(job_input)
    if error_message:
        return {"error": error_message}
    workflow = validated_data["workflow"]
    images = validated_data.get("images")

    client_id = str(uuid.uuid4())
    ws_url = f"ws://{COMFY_HOST}/ws?clientId={client_id}"

    # Start background thread for processing the job. Daemon so it will not block process exit.
    bg_thread = threading.Thread(target=process_job_background, args=(job_id, workflow, images, client_id), daemon=True)
    bg_thread.start()

    print(f"worker-comfyui - Accepted job {job_id}. Background processing started.")
    callback_api({"action": "accepted", "job_id": job_id})

    # Return immediately so serverless platform does not timeout on handler
    return {"status": "accepted", "job_id": job_id, "websocket": ws_url}


if __name__ == "__main__":
    print("worker-comfyui - Starting handler (fixed).")
    # Start ComfyUI in background at process start for faster first connection
    start_comfyui(wait_until_ready=False)
    runpod.serverless.start({"handler": handler})
