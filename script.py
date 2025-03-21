# Main Script for Natiq-py Script
# This script is used to export various quran related data's from third parties.

import sys
import xml.etree.ElementTree as ET
from lib.quran import Quran, Mushaf
import json

def export_quran(file_path, pretty = False):
    with open(file_path, 'r') as file:
        content = file.read().encode("utf-8")

    root = ET.fromstring(content)

    quran = Quran(Mushaf(1, "hafs", "hafs", "tanzil")).surahs_from_xml(root)

    result = json.dumps(quran, default=vars, ensure_ascii=False, indent=(pretty and 4) or None)

    with open("quran.json", "w", encoding="utf-8") as file:
        file.write(result)


def main(args):
    command = args[1]
    match command:
        case "quran":
            pretty = (args[3] == "--pretty") if len(args) > 3 else False
            export_quran(args[2], pretty)

if __name__ == "__main__":
    main(sys.argv)