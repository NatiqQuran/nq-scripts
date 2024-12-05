#!/usr/bin/env python3

import sys
import json
import psycopg2

USAGE_TEXT = "./divider.py [mode = ayah | word] [input_file] [database_name] [database_host_url] [database_user] [database_password] [database_port]"

def maybe_create_account(cur, username):
    cur.execute("INSERT INTO app_accounts(username, account_type) VALUES (%s, %s) ON CONFLICT (username) DO NOTHING RETURNING id",
                (username, "user"))
    cur.execute(f"select id from app_accounts where username = '{username}'")

    account_id = cur.fetchone()

    if account_id != None:
        # Also we must create a User for this account
        # metadata['author']
        cur.execute(
            "INSERT INTO app_users(account_id, language) VALUES (%s, %s) ON CONFLICT (account_id) DO NOTHING RETURNING id", (account_id, "en"))

    return account_id

def create_ayah_divide(cur,ayah_id, divider_account_id, type):
    cur.execute("INSERT INTO quran_ayah_divide(creator_user_id, ayah_id, divider_account_id, type) VALUES (1, %s, %s, %s)", (ayah_id, divider_account_id, type))

def create_word_divide(cur, word_id, divider_account_id, type):
    cur.execute("INSERT INTO quran_word_divide(creator_user_id, word_id, divider_account_id, type) VALUES (1, %s, %s, %s)", (word_id, divider_account_id, type))

def get_ayah(cur, surah_number, ayah_number):
    cur.execute("""SELECT (qa.id) FROM quran_surahs qs
        INNER JOIN quran_ayahs qa
        ON qa.surah_id = qs.id
        WHERE qs.number = %s AND qa.ayah_number = %s""", (surah_number, ayah_number))

    return cur.fetchone()

def get_word(cur, surah_number, ayah_number, word_number):
    cur.execute("""SELECT (qw.id) FROM quran_surahs qs
        INNER JOIN quran_ayahs qa
        ON qa.surah_id = qs.id
        INNER JOIN quran_words qw
        ON qw.ayah_id = qa.id
        WHERE qs.number = %s AND qa.ayah_number = %s
        ORDER BY qw.id""", (surah_number, ayah_number))

    return cur.fetchall()[word_number - 1][0]

def get_surah_and_ayah_number(string):
    splited = string.split(":")

    return (int(splited[0]), int(splited[1]))

def get_surah_and_ayah_and_word_number(string):
    splited = string.split(":")

    return (int(splited[0]), int(splited[1]), int(splited[2]))


def divide_ayah(config, cur):
    for val in config:
        id = maybe_create_account(cur, val["name"])
        for i in val["list"]:
            surah_number, ayah_number = get_surah_and_ayah_number(i)
            ayah_id = get_ayah(cur, surah_number, ayah_number)
            create_ayah_divide(cur, ayah_id, id, val["type"])

def divide_word(config, cur):
    for val in config:
        id = maybe_create_account(cur, val["name"])
        for i in val["list"]:
            surah_number, ayah_number, word_number = get_surah_and_ayah_and_word_number(i)
            word_id = get_word(cur, surah_number, ayah_number, word_number)
            create_word_divide(cur, word_id, id, val["type"])

def main(args):
    if len(args) < 6:
        print("Invalid args!\n")
        print(USAGE_TEXT)
        exit(1)

    mode = args[1]
    input_path = args[2]
    database = args[3]
    host = args[4]
    user = args[5]
    password = args[6]
    port = args[7]

    with open(input_path, 'r') as file:
        input = file.read()

    conn = psycopg2.connect(database=database, host=host,user=user, password=password, port=port)
    parsed = json.loads(input)

    cur = conn.cursor()
    match mode:
        case "ayah":
            divide_ayah(parsed, cur)
        case "word":
            divide_word(parsed, cur)
        case _:
            print("Invalid mode!")
            exit(1)
    conn.commit()


if __name__ =="__main__":
    main(sys.argv)
