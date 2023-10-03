#!/usr/bin/env python3

# This script will create natiq essential quran tables
# quran_ayahs | quran_words | quran_surahs
#
# This script will generate table creation sql and execute's into 
# the given database.
#
# (nq-team)

import hashlib
import sys
import xml.etree.ElementTree as ET
import psycopg2

TANZIL_QURAN_SOURCE_HASH = "a22c0d515c37a5667160765c2d1d171fa4b9d7d8778e47161bb0fe894cf61c1d"

INSERTABLE_QURAN_MUSHAF_TABLE = "mushafs(id, name, source, bismillah_text)"
INSERTABLE_QURAN_SURAH_TABLE = "quran_surahs(name, period, number, bismillah_status, bismillah_as_first_ayah, mushaf_id)"
INSERTABLE_QURAN_WORDS_TABLE = "quran_words(ayah_id, word)"
INSERTABLE_QURAN_AYAHS_TABLE = "quran_ayahs(surah_id, ayah_number, sajdeh)"

BISMILLAH = "بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ"

USAGE_TEXT = "./quran_parser [xml_file_path] [database_name] [database_host_url] [database_user] [database_password] [database_port]"

# The surah, ayah number has the sajdeh
# There are 3 types we must provide to the user
# vajib, mustahab and none
# if the ayah is not available in this list then return its sajdeh as none
sajdahs = {
    (32, 15): "vajib",
    (41, 37): "vajib",
    (53, 62): "vajib",
    (96, 19): "vajib",
    (7, 206): "mustahab",
    (13, 15): "mustahab",
    (16, 50): "mustahab",
    (17, 109): "mustahab",
    (19, 58): "mustahab",
    (22, 18): "mustahab",
    (25, 60): "mustahab",
    (27, 26): "mustahab",
    (38, 24): "mustahab",
    (84, 21): "mustahab",
}

def exit_err(msg):
    exit("Error: " + msg)

def exit_usage():
    exit("Usage: " + USAGE_TEXT)

# This will hash the source
# and check it to be equal to
# tanzil source hash
def validate_tanzil_quran(source):
    m = hashlib.sha256()
    m.update(source)

    return m.hexdigest() == TANZIL_QURAN_SOURCE_HASH


def insert_to_table(i_table, values):
    return f'INSERT INTO {i_table} VALUES {values};'


# the will parse the quran-source and
# creates a sql for quran surahs table
def parse_quran_suarhs_table(root, mushaf_id):
    result = []
    surah_num = 1

    for child in root:
        surah_name = child.attrib['name']
        first_ayah = root[surah_num - 1][0]
        if first_ayah.attrib['text'] == BISMILLAH:
            # also set the mushaf_id
            result.append(
                f"('{surah_name}', NULL, {surah_num}, true, true, {mushaf_id})")

        else:
            first_ayah_bismillah_status = first_ayah.get('bismillah', False)

            status = 'true' if first_ayah_bismillah_status != False else 'false'

            result.append(
                f"('{surah_name}', NULL, {surah_num}, '{status}', false, {mushaf_id})")

        surah_num += 1

    return insert_to_table(INSERTABLE_QURAN_SURAH_TABLE, ",\n".join(result))


# this will parse the ayahs
# and split the words and save it
# to the quran-words table
def parse_quran_words_table(root):
    result = []
    ayah_number = 1

    for aya in root.iter('aya'):
        # remove the every sajdeh char in the text
        # by replacing it with empty string
        ayahtext_without_sajdeh = aya.attrib['text'].replace('۩', '')

        # Get the array of aya words
        words = ayahtext_without_sajdeh.split(" ")

        # Map and change every word to a specific format
        values = list(map(lambda word: f"({ayah_number}, '{word}')", words))

        # Join the values with ,\n
        result.append(",\n".join(values))

        # Next
        ayah_number += 1

    return insert_to_table(INSERTABLE_QURAN_WORDS_TABLE, ",\n".join(result))


# This will parse the quran-ayahs table
def parse_quran_ayahs_table(root):
    result = []
    sura_number = 0

    # We just need surah_id and ayah number and sajdeh enum
    i = 1
    for aya in root.iter('aya'):
        aya_index = aya.attrib['index']
        # Get the sajdeh status of ayah from sajdahs dict
        # if its not there then return none string
        sajdah_status = sajdahs.get((sura_number, int(aya_index)), "none")

        if aya_index == "1":
            sura_number += 1

        result.append(f"({sura_number}, {aya_index}, '{sajdah_status}')")
        i += 1

    print(i)

    return insert_to_table(INSERTABLE_QURAN_AYAHS_TABLE, ",\n".join(result))


def main(args):
    if len(args) < 7:
        print("Invalid args!\n")
        exit_usage()

    # Get the quran path
    quran_xml_path = args[1]

    # Get the database information
    database = args[2]
    host = args[3]
    user = args[4]
    password = args[5]
    port = args[6]

    # Open file
    quran_source = open(quran_xml_path, "r")

    # Read to string
    quran_source_as_string = quran_source.read().encode('utf-8')

    # We dont need file anymore
    quran_source.close()

    # Validate the source
    if validate_tanzil_quran(quran_source_as_string) == False:
        exit_err("Please use the orginal Tanzil Quran Source")

    # Parse the quran xml file string
    # To a XML object so we can use it in generating sql
    root = ET.fromstring(quran_source_as_string)

    # parse the first table  : quran_ayahs
    # TODO find out the latest id and set it to the mushaf_id
    quran_surahs_table = parse_quran_suarhs_table(root, 2)

    # parse the second table : quran_words
    quran_words_table = parse_quran_words_table(root)

    # parse the third table  : quran_surahs
    quran_ayahs_table = parse_quran_ayahs_table(root)

    # Collect all the data to one string
    # order of the string matters, changing it will cause an error
    # when executing sql to psql
    final_sql_code = f'{quran_surahs_table}\n{quran_ayahs_table}\n{quran_words_table}'

    # Connect to the database
    conn = psycopg2.connect(database=database, host=host,
                            user=user, password=password, port=port)

    # We create the cursor
    cur = conn.cursor()

    # Insert hafs mushaf to the mushafs table
    hafs_sql = insert_to_table(
        INSERTABLE_QURAN_MUSHAF_TABLE, f"(2, 'hafs', 'tanzil', '{BISMILLAH}')")

    # Execute the final sql code and mushaf one
    cur.execute(hafs_sql)
    cur.execute(final_sql_code)

    # Commit the changes
    conn.commit()

    # The end of the program
    cur.close()
    conn.close()


if __name__ == "__main__":
    main(sys.argv)
