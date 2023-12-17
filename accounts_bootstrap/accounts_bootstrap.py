#!/usr/bin/env python3

import sys
import psycopg2

USAGE_TEXT = "./accounts_bootstrap.py [database_name] [database_host_url] [database_user] [database_password] [database_port]"

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
    if len(args) < 6:
        print("Invalid args!\n")
        exit(1)

    # Get the database information
    database = args[1]
    host = args[2]
    user = args[3]
    password = args[4]
    port = args[5]

    # Connect to the database
    conn = psycopg2.connect(database=database, host=host,
                            user=user, password=password, port=port)

    # We create the cursor
    cur = conn.cursor()

    _ = create_user(cur, "bootstrap_bot")

    conn.commit()

    cur.close()
    conn.close()

    print("* user/account bootstrap_bot created")


if __name__ == "__main__":
    main(sys.argv)
