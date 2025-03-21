# Main Script for Natiq-py Script
# This script is used to export various quran related data's from third parties.

import sys
import xml.etree.ElementTree as ET
from lib.quran import Quran, Mushaf
import json

def export_quran(file_path, mushaf_id, mushaf_name, mushaf_full_name, mushaf_source,pretty = False,):
    with open(file_path, 'r') as file:
        content = file.read().encode("utf-8")

    root = ET.fromstring(content)

    quran = Quran(Mushaf(mushaf_id, mushaf_name, mushaf_full_name, mushaf_source)).surahs_from_xml(root)

    result = json.dumps(quran, default=vars, ensure_ascii=False, indent=(pretty and 4) or None)

    with open("quran.json", "w", encoding="utf-8") as file:
        file.write(result)


def main(args):
    command = args[1]
    match command:
        case "quran":
            mushaf_id = int(args[3])
            mushaf_name = args[4]
            mushaf_full_name = args[5]
            mushaf_source = args[6]
            pretty = (args[7] == "--pretty") if len(args) > 6 else False
            export_quran(args[2], mushaf_id, mushaf_name, mushaf_full_name, mushaf_source,pretty)

if __name__ == "__main__":
    main(sys.argv)