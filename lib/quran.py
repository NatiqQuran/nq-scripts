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

class Mushaf():
    def __init__(self, short_name, name, source):
        self.name = name
        self.short_name = short_name
        self.source = source

BISMILLAH = "بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ"

class Surah():
    def __init__(self, name, number):
        self.name = name
        self.period = periods.get(number)
        self.number = number
        self.ayahs = []

    def ayahs_from_xml(self, surah):
        ayahs = []

        for ayah in surah.findall('aya'):
            is_bismillah = ayah.attrib['text'] == BISMILLAH
            aya_index = ayah.attrib['index']

            ayahs.append(Ayah(
                self.number,
                int(aya_index),
                is_bismillah,
                ayah.attrib.get('bismillah', None),
            ).words_from_xml(ayah))

        self.ayahs=ayahs

        return self



class Word():
    def __init__(self, text):
        self.text = text

class Ayah():
    def __init__(self,  surah_number, ayah_number, is_bismillah, bismillah_text):
        self.number = ayah_number
        self.sajdah = sajdahs.get((surah_number, ayah_number), None)
        self.is_bismillah = is_bismillah
        self.bismillah_text = bismillah_text
        self.words = []

    def words_from_xml(self, ayah):
        # remove the every sajdah char in the text
        # by replacing it with empty string
        ayahtext_without_sajdah = ayah.attrib['text'].replace('۩', '')

        # Get the array of aya words
        words = ayahtext_without_sajdah.split(" ")

        # Map and change every word to a specific format
        # 1 is the creator_user_id
        values = list(map(lambda word: Word(word), words))

        self.words = values

        return self


class Quran():
    def __init__(self, mushaf):
        self.mushaf = mushaf
        self.surahs = []
    
    def surahs_from_xml(self, root):
        for surah in root.iter('sura'):
            surah = Surah(surah.attrib['name'], int(surah.attrib['index'])).ayahs_from_xml(surah)
            self.surahs.append(surah)
        return self