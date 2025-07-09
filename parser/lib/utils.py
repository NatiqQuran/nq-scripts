import re
import os

# Remove comments from xml
# WHY: tanzil translations has an faulty comment syntax
def remove_comments_from_xml(source):
    # We filter out the comments of xml file and
    # return it, we use the regex with re library
    return re.sub("(<!--.*?-->)", "", source.decode('utf-8'), flags=re.DOTALL)

def files_in_dir(dir_path):
    return list(os.scandir(dir_path))