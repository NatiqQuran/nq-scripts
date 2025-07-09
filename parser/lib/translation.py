import os

class AyahTranslation():
    def __init__(self, text, ayah_number):
        self.number = ayah_number
        self.text = text

class TranslationSurah():
    def __init__(self, number, name):
        self.number = number
        self.name = name
        self.ayah_translations = []

    # Get ayah translations
    # This will get all of the ayahs
    def ayah_translations_from_xml(self, surah):
        for ayah in surah.findall('aya'):
            text = ayah.attrib["text"].replace("'", "&quot;")
            number = int(ayah.attrib["index"])

            self.ayah_translations.append(AyahTranslation(text, number))

        return self

class Translation():
    def __init__(self, mushaf, language, source, bismillah_text, translator_username, release_date = None):
        self.mushaf = mushaf
        self.language = language
        self.source = source
        self.bismillah_text = bismillah_text
        self.translator_username = translator_username
        self.release_date = release_date
        self.surahs = []

    def surahs_from_xml(self, root):
        for surah in root.iter('sura'):
            s = TranslationSurah(int(surah.attrib['index']), surah.attrib['name'])\
                .ayah_translations_from_xml(surah)
            self.surahs.append(s)

        return self
    

def translation_metadata(file_path):
    splited = os.path.split(file_path)

    # we split the file name to get the metadata
    # example: en.mahdi.xml -> [en, mahdi, xml]
    splited_file_name = splited[1].split('.')

    return (splited_file_name[0],splited_file_name[1])

