import re
import nltk
from nltk.corpus import stopwords
from nltk.stem import PorterStemmer
from nltk.stem.snowball import FrenchStemmer
from nltk.tokenize import word_tokenize


try:
    nltk.data.find('tokenizers/punkt')
    nltk.data.find('corpora/stopwords')
    nltk.download('punkt_tab')
except LookupError:
    nltk.download('punkt')
    nltk.download('stopwords')

class TextPreprocessor:
    def __init__(self):
        self.english_stemmer = PorterStemmer()
        self.french_stemmer = FrenchStemmer()
        self.english_stop_words = set(stopwords.words('english'))
        self.french_stop_words = set(stopwords.words('french'))
        
    def detect_language(self, text):
        """
        Détecte si le texte est plutôt en français ou en anglais
        en comptant les mots spécifiques à chaque langue
        """
        if not text:
            return 'english'  # Par défaut
            
        # Mots spécifiques au français
        french_specific = set(['je', 'tu', 'il', 'elle', 'nous', 'vous', 'ils', 'elles', 
                            'le', 'la', 'les', 'un', 'une', 'des', 'ce', 'cette', 
                            'mon', 'ton', 'son', 'notre', 'votre', 'leur',
                            'bonjour', 'merci', 'au revoir', 'salut', 'oui', 'non'])
                            
        # Mots spécifiques à l'anglais
        english_specific = set(['i', 'you', 'he', 'she', 'we', 'they', 
                             'the', 'a', 'an', 'this', 'these', 'those',
                             'my', 'your', 'his', 'her', 'our', 'their',
                             'hello', 'thank', 'goodbye', 'hi', 'yes', 'no'])
        
        # Tokenizer le texte et compter les occurrences
        tokens = word_tokenize(text.lower())
        
        french_count = sum(1 for token in tokens if token in french_specific)
        english_count = sum(1 for token in tokens if token in english_specific)
        
        return 'french' if french_count > english_count else 'english'
    
    def preprocess(self, text):
        """Prétraite un texte en détectant sa langue et en appliquant les traitements appropriés"""
        if text is None or text.strip() == "":
            return ""
            
        # Conversion en minuscules
        text = text.lower()
        
        # Détection de la langue
        language = self.detect_language(text)
        
        # Choisir les stop words et le stemmer en fonction de la langue
        stop_words = self.french_stop_words if language == 'french' else self.english_stop_words
        stemmer = self.french_stemmer if language == 'french' else self.english_stemmer
        
        # Suppression des caractères spéciaux et des chiffres
        text = re.sub(r'[^\w\s]', ' ', text)
        text = re.sub(r'\d+', ' ', text)
        
        # Tokenization
        tokens = word_tokenize(text)
        
        # Suppression des stop words et stemming
        tokens = [stemmer.stem(token) for token in tokens if token not in stop_words]
        
        return ' '.join(tokens)
