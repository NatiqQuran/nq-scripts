import sys
import os
import requests
import getpass
import json
import glob

TOKEN_FILE = os.path.expanduser("~/.importer_token")

# Send the file as multipart/form-data
def send_file_to_api(file_path, api_url, token=None):
    with open(file_path, "rb") as file:
        files = {
            "file": (os.path.basename(file_path), file, "application/json")
        }
        headers = {}
        if token:
            headers["Authorization"] = f"Token {token}"
        response = requests.post(f'{api_url}/mushafs/import/', files=files, headers=headers)
        return response

def send_translation_to_api(file_path, api_url, token=None):
    with open(file_path, "rb") as file:
        files = {
            "file": (os.path.basename(file_path), file, "application/json")
        }
        headers = {}
        if token:
            headers["Authorization"] = f"Token {token}"
        response = requests.post(f'{api_url}/translations/import/', files=files, headers=headers)
        return response

def login(api_url, username=None, password=None):
    if username is None:
        username = input("Username: ")
    if password is None:
        import getpass
        password = getpass.getpass("Password: ")
    data = {"username": username, "password": password}
    try:
        response = requests.post(f"{api_url}/auth/login/", json=data)
        if response.status_code == 200:
            token = response.json().get("token")
            if token:
                with open(TOKEN_FILE, "w") as f:
                    f.write(token)
                print("Login successful. Token saved.")
            else:
                print("Login failed: No token in response.")
        else:
            print(f"Login failed: {response.status_code} {response.text}")
    except Exception as e:
        print(f"Login error: {e}")
        sys.exit(1)

def load_token():
    if os.path.exists(TOKEN_FILE):
        with open(TOKEN_FILE, "r") as f:
            return f.read().strip()
    return None

def main(args):
    if len(args) < 2:
        print("Usage: python script.py <command> [args...]")
        print("Commands:")
        print("  login <api_url> [username password] [--non-interactive]")
        print("  import-mushaf <input_json_file> <api_url>")
        print("  import-translations <translations_dir> <api_url>")
        sys.exit(1)

    command = args[1]

    if command == "login":
        # Check for --not-interactive flag
        if '--non-interactive' in args:
            try:
                flag_index = args.index('--non-interactive')
                # Remove the flag for easier indexing
                args_wo_flag = args[:flag_index] + args[flag_index+1:]
                if len(args_wo_flag) != 5:
                    print("Usage: python script.py login <api_url> <username> <password> --not-interactive")
                    sys.exit(1)
                api_url = args_wo_flag[2]
                username = args_wo_flag[3]
                password = args_wo_flag[4]
                login(api_url, username, password)
                return
            except Exception:
                print("Usage: python script.py login <api_url> <username> <password> --not-interactive")
                sys.exit(1)
        else:
            if len(args) == 3:
                api_url = args[2]
                login(api_url)
                return
            elif len(args) == 5:
                api_url = args[2]
                username = args[3]
                password = args[4]
                login(api_url, username, password)
                return
            else:
                print("Usage: python script.py login <api_url> [username password] [--not-interactive]")
                sys.exit(1)
    elif command == "import-mushaf":
        if len(args) != 4:
            print("Usage: python script.py import-mushaf <input_json_file> <api_url>")
            sys.exit(1)
        input_file = args[2]
        api_url = args[3]
        if not os.path.isfile(input_file):
            print(f"Error: File '{input_file}' does not exist.")
            sys.exit(1)
        if not input_file.endswith('.json'):
            print("Error: Input file must be a .json file.")
            sys.exit(1)
        token = load_token()
        try:
            response = send_file_to_api(input_file, api_url, token)
            print(f"Status code: {response.status_code}")
            try:
                print("Response:", response.json())
            except Exception:
                print("Response (non-JSON):", response.text)
        except Exception as e:
            print(f"Failed to send file: {e}")
            sys.exit(1)
    elif command == "import-translations":
        if len(args) != 4:
            print("Usage: python script.py import-translations <translations_dir> <api_url>")
            sys.exit(1)
        translations_dir = args[2]
        api_url = args[3]
        if not os.path.isdir(translations_dir):
            print(f"Error: Directory '{translations_dir}' does not exist.")
            sys.exit(1)
        token = load_token()
        json_files = glob.glob(os.path.join(translations_dir, '*.json'))
        if not json_files:
            print(f"No .json files found in directory '{translations_dir}'.")
            sys.exit(1)
        for file_path in json_files:
            print(f"Importing {file_path}...")
            try:
                response = send_translation_to_api(file_path, api_url, token)
                print(f"  Status code: {response.status_code}")
                try:
                    print("  Response:", response.json())
                except Exception:
                    print("  Response (non-JSON):", response.text)
            except Exception as e:
                print(f"  Failed to import {file_path}: {e}")
    elif command == "import-translation":
        if len(args) != 4:
            print("Usage: python script.py import-translation <input_json_file> <api_url>")
            sys.exit(1)
        input_file = args[2]
        api_url = args[3]
        if not os.path.isfile(input_file):
            print(f"Error: File '{input_file}' does not exist.")
            sys.exit(1)
        if not input_file.endswith('.json'):
            print("Error: Input file must be a .json file.")
            sys.exit(1)
        token = load_token()
        try:
            response = send_translation_to_api(input_file, api_url, token)
            print(f"Status code: {response.status_code}")
            try:
                print("Response:", response.json())
            except Exception:
                print("Response (non-JSON):", response.text)
        except Exception as e:
            print(f"Failed to send file: {e}")
            sys.exit(1)
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)

if __name__ == "__main__":
    main(sys.argv)