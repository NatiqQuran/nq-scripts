# This script will create natiq essential translations tables
# Tables this script will create ->
# translations_text | translations
# More clearly the result of this script is the sql code
# that will create tables and insert the data (translation)
#
# (nq-team)

import sys
import os
import xml.etree.ElementTree as ET
import psycopg2
import re

INSERTABLE_TRANSLATIONS_TEXT = "translations_text(text, translation_id, ayah_id)"


# Exits with an error
# example: Error: cant read not xml file as a translation
def exit_err(msg):
    exit("Error: " + msg)


# Returns the insert sql script for specific table
def insert_to_table(i_table, values):
    return f'INSERT INTO {i_table} VALUES {values};'


def translations(translations_folder_path):
    return list(os.scandir(translations_folder_path))


def remove_comments_from_xml(source):
    # We filter out the comments of xml file and
    # return it, we use the regex with re library
    return re.sub("(<!--.*?-->)", "", source.decode('utf-8'), flags=re.DOTALL)


def create_translation_table(root, translation_id):
    result = []

    # calculating the ayahs
    ayah_num = 1

    for child in root.iter('aya'):
        # we replace the ' char with &quot; bequase the postgres
        # cant insert the string that has a ' char.
        surah_text = child.attrib["text"].replace("'", "&quot;")

        # We append this aya to the final sql
        # example: ("some quran text", 1, 1)
        result.append(
            f"('{surah_text}', {translation_id}, {ayah_num})")

        ayah_num += 1

    # finally return the final script
    return insert_to_table(INSERTABLE_TRANSLATIONS_TEXT, ",".join(result))


def check_the_translation_file(translation):
    # Split into the name and extention
    splited_path = os.path.splitext(translation)

    # Check if file format is correct
    if splited_path[1] != ".xml":
        exit_err("Quran Source must be an xml file")


def translation_metadata(file_path):
    splited = os.path.split(file_path)

    # we split the file name to get the metadata
    # example: en.mahdi.xml -> [en, mahdi, xml]
    splited_file_name = splited[1].split('.')

    return {"language": splited_file_name[0], "author": splited_file_name[1], "type": splited_file_name[2]}


def main(args):

    # Get the database information
    database = args[2]
    host = args[3]
    user = args[4]
    password = args[5]
    port = args[6]

    # Connect to the database
    conn = psycopg2.connect(database=database, host=host,
                            user=user, password=password, port=port)

    # Get the quran path
    translations_folder_path = args[1]

    # Get the translations path, from the translations folder
    translations_list = translations(translations_folder_path)

    # Iterate to the each file (translation)
    for translation in translations_list:
        # Create a new cursor (idk what is this)
        cur = conn.cursor()

        # Get the file path
        path = translation.path

        # Gather the metadata from path
        metadata = translation_metadata(path)

        print(f'Parsing {path}')

        # This script can just parse the xml format
        # although the is not a best way to find file format
        if metadata["type"] != "xml":
            exit_err("This program can just parse the xml type of translations")

        # we open the translation file
        translation_source = open(path, "r")
        # we read it
        tranlation_text = translation_source.read().encode('utf-8')
        # we close it
        # we must close the file because we are in the loop
        translation_source.close()

        # We will create a account for every translator
        cur.execute("INSERT INTO app_accounts(username, account_type) VALUES (%s, %s) ON CONFLICT (username) DO NOTHING RETURNING id",
                    (metadata['author'], "user"))

        # Get the account id from executed sql
        account_id = cur.fetchone()

        # if this is a new account
        if account_id != None:
            # Also we must create a User for this account
            cur.execute(
                "INSERT INTO app_users(account_id, last_name) VALUES (%s, %s) ON CONFLICT (account_id) DO NOTHING", (account_id, metadata['author']))
        else:
            # handle the existed account
            print("The translator account exists, skiping user creation")
            cur.execute(
                "SELECT id FROM app_accounts WHERE username=%s", (metadata['author'], ))

            # get the id and set it to the account_id var
            account_id = cur.fetchone()

        # commit the chages
        conn.commit()

        # Insert a translation in translations table
        cur.execute("INSERT INTO translations(translator_id, language) VALUES (%s, %s) RETURNING id",
                    (account_id[0], metadata["language"]))

        # Remove the comments from translation file content
        translation_text_clean = remove_comments_from_xml(tranlation_text)

        print("parsing xml")

        # We are parsing the xml
        root = ET.fromstring(translation_text_clean)
        # This will return the INSERT script that will create
        # the new translation_text field
        translations_text_data = create_translation_table(
            root, cur.fetchone()[0])

        print("executing")

        # we execute the script
        cur.execute(translations_text_data)

        # commit the changes
        conn.commit()

        # close the cursor
        # is this necessary?
        cur.close()

    # close the connection from psql
    # this is not necessary because program ends here
    conn.close()


if __name__ == "__main__":
    main(sys.argv)
