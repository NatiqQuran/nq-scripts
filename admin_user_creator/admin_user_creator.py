#!/usr/bin/env python3

import sys
import psycopg2

USAGE_TEXT = "./admin_user_creator.py [database_name] [database_host_url] [database_user] [database_password] [database_port] [admin_email] [admin_username]"

# This will create user with account
# If exists will return the id
def create_user(cur, username, email):
    # We will create a account for every translator
    cur.execute("INSERT INTO app_accounts(username, account_type) VALUES (%s, %s) ON CONFLICT (username) DO NOTHING RETURNING id",
                (username, "user"))

    print("* Account Created")

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
        # handle the existed account
        cur.execute(
            "SELECT id FROM app_accounts WHERE username=%s", (username, ))

        # get the id and set it to the account_id var
        account_id = cur.fetchone()

        cur.execute(
            "SELECT id FROM app_users WHERE account_id=%s", (account_id, ))

        print("* User Created")
        # Get the id of user id
        user_id = cur.fetchone()

        # create email
        cur.execute('INSERT INTO app_emails (account_id, creator_user_id, email,verified,"primary",deleted) VALUES (%s,%s, %s,true,true,false)', (1,1,email, ))
        print("* Email Created")

        cur.execute('INSERT INTO app_permissions (creator_user_id, account_id,"object","action") VALUES (%s,%s, %s, %s)', (1,1,"permission", "create"))
        cur.execute('INSERT INTO app_permissions (creator_user_id, account_id,"object","action") VALUES (%s,%s, %s, %s)', (1,1,"permission", "delete"))
        cur.execute('INSERT INTO app_permissions (creator_user_id, account_id,"object","action") VALUES (%s,%s, %s, %s)', (1,1,"permission", "view"))
        cur.execute('INSERT INTO app_permissions (creator_user_id, account_id,"object","action") VALUES (%s,%s, %s, %s)', (1,1,"permission", "edit"))
        cur.execute('INSERT INTO app_permissions (creator_user_id, account_id,"object","action") VALUES (%s,%s, %s, %s)', (1,1,"user", "view"))
        print("* Permissions where given to the user")

    return (account_id[0], user_id[0])

def main(args):
    if len(args) < 6:
        print("Invalid args!\n")
        print(USAGE_TEXT)

        exit(1)

    # Get the database information
    database = args[1]
    host = args[2]
    user = args[3]
    password = args[4]
    port = args[5]
    admin_email = args[6]
    admin_username = args[7]

    # Connect to the database
    conn = psycopg2.connect(database=database, host=host,
                            user=user, password=password, port=port)
    cur = conn.cursor()

    _,_ = create_user(cur, admin_username, admin_email)

    conn.commit()

    cur.close()
    conn.close()


if __name__ == "__main__":
    main(sys.argv)
