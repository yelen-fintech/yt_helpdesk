from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
import numpy as np

class EmailLogisticRegression:
    def __init__(self):
        self.vectorizer = TfidfVectorizer(max_features=1000)
        self.category_classifier = LogisticRegression(max_iter=1000, C=1.0)
        self.priority_classifier = LogisticRegression(max_iter=1000, C=1.0)
        self.is_trained = False
    
    def preprocess(self, subjects, bodies):
        # Extract features from subject and body separately
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
