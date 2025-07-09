# Importer Script

A command-line tool for importing mushaf and translation data into your API via HTTP requests.

## Features
- **Login** with API credentials (interactive or non-interactive)
- **Import a single mushaf** file
- **Import a single translation** file
- **Bulk import translations** from a directory (sequentially)

## Requirements
- Python 3.6+
- See `requirements.txt`

Install dependencies:
```bash
pip install -r requirements.txt
```

## Usage

### 1. Login
Authenticate and store your API token for future requests.

**Interactive:**
```bash
python script.py login <api_url>
```
You will be prompted for username and password.

**Non-interactive:**
```bash
python script.py login <api_url> <username> <password> --non-interactive
```

---

### 2. Import a Mushaf
Import a single mushaf JSON file:
```bash
python script.py import-mushaf <input_json_file> <api_url>
```

---

### 3. Import a Single Translation
Import a single translation JSON file:
```bash
python script.py import-translation <input_json_file> <api_url>
```

---

### 4. Bulk Import Translations
Import all `.json` files in a directory as translations (sequentially, one after another):
```bash
python script.py import-translations <translations_dir> <api_url>
```

---

## Authentication
- On successful login, a token is saved to `~/.importer_token` and used for subsequent imports.
- If the token is missing or expired, re-run the login command.

## Notes
- All import requests use `multipart/form-data` as required by the API.
- Bulk import processes files sequentially (not in parallel).
- Error messages and API responses are printed for each operation.

## Example
```bash
python script.py login http://localhost:8000
python script.py import-mushaf my_mushaf.json http://localhost:8000
python script.py import-translation my_translation.json http://localhost:8000
python script.py import-translations ./translations http://localhost:8000
``` 