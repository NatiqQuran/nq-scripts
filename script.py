# Main Script for Natiq-py Script
# This script is used to export various quran related data's from third parties.

import sys
import xml.etree.ElementTree as ET
from lib.quran import Quran, Mushaf
from lib.translation import Translation, translation_metadata
from lib.utils import remove_comments_from_xml, files_in_dir
import json
import os

USAGE = """Natiq Quran Exporter
Usage:
    python script.py quran <path_to_quran_xml_file> <mushaf_name> <mushaf_full_name> <mushaf_source> [--pretty]
    python script.py translation <path_to_translation_xml_file> <mushaf_short_name> <language> <author> [--pretty]
    python script.py translation-bulk <path_to_translations_dir> <output_dir> <mushaf_short_name> [--pretty]
"""

def quran_xml_into_json(file_path, mushaf_name, mushaf_full_name, mushaf_source,pretty = False,):
    with open(file_path, 'r') as file:
        content = file.read().encode("utf-8")

    root = ET.fromstring(content)

    quran = Quran(Mushaf(mushaf_name, mushaf_full_name, mushaf_source))\
            .surahs_from_xml(root)

    return json.dumps(quran, default=vars, ensure_ascii=False, indent=(pretty and 4) or None)

def translation_xml_into_json(file_path, mushaf, source, language, author, pretty = False):
    with open(file_path, 'r') as file:
        content = file.read().encode("utf-8")

    #(language, author) = translation_metadata(file_path)
    root = ET.fromstring(remove_comments_from_xml(content))
    first_ayah_text = root[0][0].attrib['text']

    translation = Translation(mushaf, language, source, first_ayah_text, author)\
            .surahs_from_xml(root)

    return json.dumps(translation, default=vars, ensure_ascii=False, indent=(pretty and 4) or None)

def main(args):
    if len(args) <= 1:
        print(USAGE)
        exit(0)
    command = args[1]
    match command:
        case "quran":
            mushaf_name = args[3]
            mushaf_full_name = args[4]
            mushaf_source = args[5]
            pretty = (args[6] == "--pretty") if len(args) > 7 else False
            json = quran_xml_into_json(args[2], mushaf_name, mushaf_full_name, mushaf_source,pretty)
            with open(f"{mushaf_name}.json", "w", encoding="utf-8") as file:
                file.write(json)

        case "translation":
            translation_path = args[2]
            mushaf = args[3]
            source = "tanzil.net" # HARD CODED
            language = args[4]
            author = args[5]
            pretty = (args[6] == "--pretty") if len(args) > 6 else False
            json = translation_xml_into_json(translation_path, mushaf, source, language, author, pretty)
            with open(f"{language}.{author}.json", "w", encoding="utf-8") as file:
                file.write(json)

        case "translation-bulk":
            source = "tanzil.net" # HARD CODED
            translations_dir_path = args[2]
            output_dir = args[3]
            mushaf = args[4]

            if not os.path.exists(output_dir):
                os.makedirs(output_dir)

            pretty = (args[5] == "--pretty") if len(args) > 5 else False

            for translation in files_in_dir(translations_dir_path):
                path = translation.path
                (language, author) = translation_metadata(path)
                json = translation_xml_into_json(path, mushaf, source, language, author, pretty)

                with open(os.path.join(output_dir, f"{language}.{author}.json"), "w", encoding="utf-8") as file:
                    file.write(json)

if __name__ == "__main__":
    main(sys.argv)