# Natiq Quran scripts
Convert raw quran data's into nq-api compatible format.
***This script only supports data from [tanzil.net](https://tanzil.net)***

# Usage
Running `script.py` without any args will print script usage

### Export Quran data
```bash
python script.py quran <path_to_quran_xml_file> <mushaf_name> <mushaf_full_name> <mushaf_source> [--pretty]
```
* `path_to_quran_xml_file` Path to raw(xml) quran file
* `mushaf_name` Mushaf short name e.g hafs
* `mushaf_full_name` Mushaf full name e.g Hafs an Asem
* `mushaf_source` Data source e.g tanzil.net
* `--pretty` Save output json with indentation(4)

### Export Translation data
#### Single Translation
```bash
python script.py translation <path_to_translation_xml_file> <source> <language> <author> [--pretty]
```
* `path_to_translation_xml_file` Path to raw(xml) translation file
* `source` Data source e.g tanzil.net
* `language` Translation language e.g en
* `author` Translator name
* `--pretty` Save output json with indentation(4)

#### Multiple Translations
***translation files should have this form of name `{language}.{author}.xml` e.g en.itani.xml***

```bash
python script.py translation-bulk <source> <path_to_translations_dir> <output_dir> [--pretty]
```
* `source` Data source e.g tanzil.net
* `path_to_translations_dir` Translations Directory e.g translations/
* `output_dir` Results output directory e.g out/
* `--pretty` Save output json with indentation(4)
