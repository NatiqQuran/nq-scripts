#!/usr/bin/env python3

import sys
import json
import psycopg2

USAGE_TEXT = "./break.py [mode = ayah | word] [input_file] [name] [database_name] [database_host_url] [database_user] [database_password] [database_port]"

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

def create_ayah_break(cur,ayah_id, owner_account_id, name):
    cur.execute("INSERT INTO quran_ayahs_breakers(creator_user_id, ayah_id, owner_account_id, name) VALUES (1, %s, %s, %s)", (ayah_id, owner_account_id, name))

def create_word_break(cur, word_id, owner_account_id, name):
    cur.execute("INSERT INTO quran_words_breakers(creator_user_id, word_id, owner_account_id, name) VALUES (1, %s, %s, %s)", (word_id, owner_account_id, name))

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


def divide_ayah(config, cur, name):
    for i in config:
        surah_number, ayah_number = get_surah_and_ayah_number(i)
        ayah_id = get_ayah(cur, surah_number, ayah_number)
        create_ayah_break(cur, ayah_id, None, name)

def divide_word(config, cur, name):
    for i in config:
        surah_number, ayah_number, word_number = get_surah_and_ayah_and_word_number(i)
        word_id = get_word(cur, surah_number, ayah_number, word_number)
        create_word_break(cur, word_id, None, name)

def main(args):
    if len(args) < 6:
        print("Invalid args!\n")
        print(USAGE_TEXT)
        exit(1)

    mode = args[1]
    input_path = args[2]
    name = args[3]
    database = args[4]
    host = args[5]
    user = args[6]
    password = args[7]
    port = args[8]

    with open(input_path, 'r') as file:
        input = file.read()

    conn = psycopg2.connect(database=database, host=host,user=user, password=password, port=port)
    parsed = json.loads(input)

    cur = conn.cursor()
    match mode:
        case "ayah":
            divide_ayah(parsed, cur, name)
        case "word":
            divide_word(parsed, cur, name)
        case _:
            print("Invalid mode!")
            exit(1)
    conn.commit()


if __name__ =="__main__":
    main(sys.argv)
