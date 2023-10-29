#!/usr/bin/env python3

# This script will send request's to some of routers of the API
# and save the response body's to files, to port the API for Blockchain's
#
# Sometimes the response of api for an table is deferent then actual table
# so we need to send actual HTTP request's to the backend to Extract the data

import sys
import requests
import json

MUSHAFS_LIST_ROUTE = "/mushaf"
SURAHS_LIST_ROUTE = "/surah"

USAGE = "./api_exporter.py {out_dir} {api_url}"

def exit_err(msg):
    print(msg)
    exit(1)

def exit_usage():
    print(USAGE)
    exit(1)

class ApiCaller:
    def __init__(self, api_url):
        self.api_url = api_url

    def validate(self, req):
        if req.status_code != 200:
            return False
        
        return True

    # Send request to a url
    # route must start with '/' char
    def get_json(self, route):
        request = requests.get(f'{self.api_url}{route}')

        if self.validate(request) == False:
            exit_err("Request failed!")

        return request.json()
        

def new_json_file(content, file_name, out_dir):
    with open(f"./{out_dir}/{file_name}.json", 'w') as file:
        file.write(content)

def get_mushafs_list(caller):
    return caller.get_json(MUSHAFS_LIST_ROUTE)
    
def get_surahs_list(caller, mushaf):
    return caller.get_json(f"{SURAHS_LIST_ROUTE}?mushaf={mushaf}")

def get_single_surah(caller, uuid, mushaf):
    return caller.get_json(f"{SURAHS_LIST_ROUTE}/{uuid}?mushaf={mushaf}")

def main(args):
    if len(args) <= 2:
        exit_usage()

    out_dir = args[1]
    api_url = args[2]

    caller = ApiCaller(api_url)

    # Save the list of mushafs
    mushafs_list = get_mushafs_list(caller)
    new_json_file(json.dumps(mushafs_list), "mushafs_list", "out")

    # Save the list of 
    surahs_list = get_surahs_list(caller, "hafs")
    new_json_file(json.dumps(surahs_list), "surahs_list", "out")

    for surah in surahs_list:
        s = get_single_surah(caller, surah["uuid"], "hafs")
        new_json_file(json.dumps(s), "surah_" + str(s["surah_number"]), "out")

if __name__ == "__main__":
    main(sys.argv)
