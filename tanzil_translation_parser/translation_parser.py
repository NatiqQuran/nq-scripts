#!/usr/bin/env python3

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

# INSERTABLE_TRANSLATIONS = "translations(creator_user_id, translator_account_id, language, source)"
INSERTABLE_TRANSLATIONS_TEXT = "translations_text(creator_user_id, text, translation_id, ayah_id)"
TRANSLATIONS_SOURCE = "tanzil"

USAGE_TEXT = "./translation_parser.py [translations_folder_path] [database_name] [database_host_url] [database_user] [database_password] [database_port]"

# Returns the insert sql script for specific table
def insert_to_table(i_table, values):
    return f'INSERT INTO {i_table} VALUES {values};'


def translations(translations_folder_path):
    return list(os.scandir(translations_folder_path))


def remove_comments_from_xml(source):
    # We filter out the comments of xml file and
    # return it, we use the regex with re library
    return re.sub("(<!--.*?-->)", "", source.decode('utf-8'), flags=re.DOTALL)


def create_translation_table(root, translation_id, creator_user_id):
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
            f"({creator_user_id}, '{surah_text}', {translation_id}, {ayah_num})")

        ayah_num += 1

    # finally return the final script
    return insert_to_table(INSERTABLE_TRANSLATIONS_TEXT, ",".join(result))


def check_the_translation_file(translation):
    # Split into the name and extention
    splited_path = os.path.splitext(translation)

    # Check if file format is correct
    if splited_path[1] != ".xml":
        print("Quran Source must be an xml file")
        exit(1)


def translation_metadata(file_path):
    splited = os.path.split(file_path)

    # we split the file name to get the metadata
    # example: en.mahdi.xml -> [en, mahdi, xml]
    splited_file_name = splited[1].split('.')

    return {"language": splited_file_name[0], "author": splited_file_name[1], "type": splited_file_name[2]}


# This will create user with account
# If exists will return the id
def create_user(cur, username):
    # We will create a account for every translator
    cur.execute("INSERT INTO app_accounts(username, account_type) VALUES (%s, %s) ON CONFLICT (username) DO NOTHING RETURNING id",
                (username, "user"))

    # Get the account id from executed sql
    account_id = cur.fetchone()
    user_id = None

    # if this is a new account
    if account_id != None:
        # Also we must create a User for this account
        # metadata['author']
        cur.execute(
            "INSERT INTO app_users(account_id, language) VALUES (%s, %s) RETURNING id", (account_id, "en"))
        user_id = cur.fetchone()
    else:
        # handle the existed account
        print("* The translator account exists, skiping user creation")
        cur.execute(
            "SELECT id FROM app_accounts WHERE username=%s", (username, ))

        # get the id and set it to the account_id var
        account_id = cur.fetchone()

        cur.execute(
            "SELECT id FROM app_users WHERE account_id=%s", (account_id, ))

        # Get the id of user id
        user_id = cur.fetchone()

    return (account_id[0], user_id[0])

def main(args):
    if len(args) < 7:
        print("Invalid args!\n")
        print(USAGE_TEXT)

        exit(1)

    # Get the database information
    database = args[2]
    host = args[3]
    user = args[4]
    password = args[5]
    port = args[6]

    # Connect to the database
    conn = psycopg2.connect(database=database, host=host, user=user, password=password, port=port)

    # Get the quran path
    translations_folder_path = args[1]

    # Get the translations path, from the translations folder
    translations_list = translations(translations_folder_path)

    i = 0

    # Iterate to the each file (translation)
    for translation in translations_list:
        # Get the file path
        path = translation.path

        # Create a new cursor (idk what is this)
        cur = conn.cursor()

        # Gather the metadata from path
        metadata = translation_metadata(path)

        print(f'* Working on {path}')

        # This script can just parse the xml format
        # although the is not a best way to find file format
        if metadata["type"] != "xml":
            print("This program can just parse the xml type of translations")
            exit(1)

        # we open the translation file
        translation_source = open(path, "r")
        # we read it
        tranlation_text = translation_source.read().encode('utf-8')
        # we close it
        # we must close the file because we are in the loop
        translation_source.close()

        author_user = create_user(cur, metadata["author"])

        # commit the chages
        conn.commit()

        # Remove the comments from translation file content
        translation_text_clean = remove_comments_from_xml(tranlation_text)

        print("* Parsing xml")

        # We are parsing the xml
        root = ET.fromstring(translation_text_clean)

        first_ayah_text = root[0][0].attrib['text']
        # Insert a translation in translations table
        cur.execute("INSERT INTO translations(mushaf_id, creator_user_id, translator_account_id, language, approved, source, bismillah_text) VALUES (%s, %s, %s, %s, %s, %s, %s) RETURNING id",
                    (2, 1, author_user[0], metadata["language"], True, TRANSLATIONS_SOURCE, first_ayah_text))

        translation_id = cur.fetchone()[0]

             # This will return the INSERT script that will create
        # the new translation_text field
        translations_text_data = create_translation_table(root, translation_id, 1)

        print("* Executing")

        # we execute the script
        cur.execute(translations_text_data)

        # commit the changes
        conn.commit()

        cur.close()

        i += 1
        print("* Successfuly added to the database.")
        print(("-" * 50))

    # close the connection from psql
    # this is not necessary because program ends here
    conn.close()

    print(f"\n* Successfully imported translations: {i}")


if __name__ == "__main__":
    main(sys.argv)
