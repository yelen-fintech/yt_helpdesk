from sklearn.feature_extraction.text import CountVectorizer
from sklearn.naive_bayes import MultinomialNB
import numpy as np

class EmailNaiveBayes:
    def __init__(self):
        self.vectorizer = CountVectorizer()
        self.category_classifier = MultinomialNB()
        self.priority_classifier = MultinomialNB()
        self.is_trained = False
    
    def preprocess(self, subjects, bodies):
        combined_texts = [f"{subject} {body}" for subject, body in zip(subjects, bodies)]
        return self.vectorizer.fit_transform(combined_texts)
    
    def train(self, emails):
        subjects = [email['subject'] for email in emails]
        bodies = [email['body'] for email in emails]
        categories = [email['category'] for email in emails]
        priorities = [email['priority'] for email in emails]
        
        X = self.preprocess(subjects, bodies)
        
        self.category_classifier.fit(X, categories)
        self.priority_classifier.fit(X, priorities)
        self.is_trained = True
        
        return {
            "num_samples": len(emails),
            "performance": {
                "category_score": "Not evaluated", 
                "priority_score": "Not evaluated"
            }
        }
    
    def classify(self, subject, body):
        if not self.is_trained:
            return {"category": "unknown", "priority": "medium", "confidence": 0.0}
        
        X = self.vectorizer.transform([f"{subject} {body}"])
        
        category = self.category_classifier.predict(X)[0]
        priority = self.priority_classifier.predict(X)[0]
        
        category_proba = np.max(self.category_classifier.predict_proba(X))
        priority_proba = np.max(self.priority_classifier.predict_proba(X))
        
        confidence = (category_proba + priority_proba) / 2
        
        return {
            "category": category, 
            "priority": priority,
            "confidence": float(confidence)
        }
