import os

class AyahTranslation():
    def __init__(self, text, ayah_number):
        self.number = ayah_number
        self.text = text

class Translation():
    def __init__(self, language, source, bismillah_text, translator_username, release_date = None):
        self.language = language
        self.source = source
        self.bismillah_text = bismillah_text
        self.translator_username = translator_username
        self.release_date = release_date
        self.ayah_translations = []
    
    # Get ayah translations
    # This will get all of the ayahs
    def ayah_translations_from_xml(self, root):
        for ayah in root.iter('aya'):
            text = ayah.attrib["text"].replace("'", "&quot;")
            number = int(ayah.attrib["index"])

            self.ayah_translations.append(AyahTranslation(text, number))

        return self

def translation_metadata(file_path):
    splited = os.path.split(file_path)

    # we split the file name to get the metadata
    # example: en.mahdi.xml -> [en, mahdi, xml]
    splited_file_name = splited[1].split('.')

    return (splited_file_name[0],splited_file_name[1])

