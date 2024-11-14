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

INSERTABLE_QURAN_MUSHAF_TABLE = "quran_mushafs(creator_user_id, id, short_name, name, source, bismillah_text)"
INSERTABLE_QURAN_SURAH_TABLE = "quran_surahs(creator_user_id, name, period, number, bismillah_status, bismillah_as_first_ayah, mushaf_id)"
INSERTABLE_QURAN_WORDS_TABLE = "quran_words(creator_user_id, ayah_id, word)"
INSERTABLE_QURAN_AYAHS_TABLE = "quran_ayahs(creator_user_id, surah_id, ayah_number, sajdah)"

BISMILLAH = "بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ"

USAGE_TEXT = "./quran_parser [xml_file_path] [database_name] [database_host_url] [database_user] [database_password] [database_port]"

# The surah, ayah number has the sajdah
# There are 3 types we must provide to the user
# vajib, mustahab and none
# if the ayah is not available in this list then return its sajdah as none
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

periods = {
    1: "makki",
    2: "madani",
    3: "madani",
    4: "madani",
    5: "madani",
    6: "makki",
    7: "makki",
    8: "madani",
    9: "madani",
    10: "makki",
    11: "makki",
    12: "makki",
    13: "madani",
    14: "makki",
    15: "makki",
    16: "makki",
    17: "makki",
    18: "makki",
    19: "makki",
    20: "makki",
    21: "makki",
    22: "madani",
    23: "makki",
    24: "madani",
    25: "makki",
    26: "makki",
    27: "makki",
    28: "makki",
    29: "makki",
    30: "makki",
    31: "makki",
    32: "makki",
    33: "madani",
    34: "makki",
    35: "makki",
    36: "makki",
    37: "makki",
    38: "makki",
    39: "makki",
    40: "makki",
    41: "makki",
    42: "makki",
    43: "makki",
    44: "makki",
    45: "makki",
    46: "makki",
    47: "madani",
    48: "madani",
    49: "madani",
    50: "makki",
    51: "makki",
    52: "makki",
    53: "makki",
    54: "makki",
    55: "madani",
    56: "makki",
    57: "madani",
    58: "madani",
    59: "madani",
    60: "madani",
    61: "madani",
    62: "madani",
    63: "madani",
    64: "madani",
    65: "madani",
    66: "madani",
    67: "makki",
    68: "makki",
    69: "makki",
    70: "makki",
    71: "makki",
    72: "makki",
    73: "makki",
    74: "makki",
    75: "makki",
    76: "madani",
    77: "makki",
    78: "makki",
    79: "makki",
    80: "makki",
    81: "makki",
    82: "makki",
    83: "makki",
    84: "makki",
    85: "makki",
    86: "makki",
    87: "makki",
    88: "makki",
    89: "makki",
    90: "makki",
    91: "makki",
    92: "makki",
    93: "makki",
    94: "makki",
    95: "makki",
    96: "makki",
    97: "makki",
    98: "madani",
    99: "madani",
    100: "makki",
    101: "makki",
    102: "makki",
    103: "makki",
    104: "makki",
    105: "makki",
    106: "makki",
    107: "makki",
    108: "makki",
    109: "makki",
    110: "madani",
    111: "makki",
    112: "makki",
    113: "makki",
    114: "makki",
}

def exit_err(msg):
    print("Error: " + msg)
    exit(1)

def exit_usage():
    print("Usage: " + USAGE_TEXT)
    exit(1)

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
        period = periods.get(surah_num)
        if first_ayah.attrib['text'] == BISMILLAH:
            # also set the mushaf_id
            # 1 is the creator_user_id
            result.append(
                f"(1, '{surah_name}', '{period}', {surah_num}, true, true, {mushaf_id})")

        else:
            first_ayah_bismillah_status = first_ayah.get('bismillah', False)

            status = 'true' if first_ayah_bismillah_status != False else 'false'

            # 1 is the creator_user_id
            result.append(
                f"(1, '{surah_name}', '{period}', {surah_num}, '{status}', false, {mushaf_id})")

        surah_num += 1

    return insert_to_table(INSERTABLE_QURAN_SURAH_TABLE, ",\n".join(result))


# this will parse the ayahs
# and split the words and save it
# to the quran-words table
def parse_quran_words_table(root):
    result = []
    ayah_number = 1

    for aya in root.iter('aya'):
        # remove the every sajdah char in the text
        # by replacing it with empty string
        ayahtext_without_sajdah = aya.attrib['text'].replace('۩', '')

        # Get the array of aya words
        words = ayahtext_without_sajdah.split(" ")

        # Map and change every word to a specific format
        # 1 is the creator_user_id
        values = list(map(lambda word: f"(1, {ayah_number}, '{word}')", words))

        # Join the values with ,\n
        result.append(",\n".join(values))

        # Next
        ayah_number += 1

    return insert_to_table(INSERTABLE_QURAN_WORDS_TABLE, ",\n".join(result))


# This will parse the quran-ayahs table
def parse_quran_ayahs_table(root):
    result = []
    surah_number = 0

    # We just need surah_id and ayah number and sajdah enum
    i = 1
    for aya in root.iter('aya'):
        aya_index = aya.attrib['index']
        # Get the sajdah status of ayah from sajdahs dict
        # if its not there then return none string
        sajdah_status = sajdahs.get((surah_number, int(aya_index)), None)

        if aya_index == "1":
            surah_number += 1

        # 1 is the creator_user_id
        if sajdah_status == None:
            result.append(f"(1, {surah_number}, {aya_index}, NULL)")
        else:
            result.append(f"(1, {surah_number}, {aya_index}, '{sajdah_status}')")
        i += 1

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
    # 1 is the creator_user_id
    hafs_sql = insert_to_table(
        INSERTABLE_QURAN_MUSHAF_TABLE, f"(1, 2, 'hafs', 'Hafs an Asem','tanzil', '{BISMILLAH}')")

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
