import json
import os
from .decision_tree import EmailDecisionTree
from .naive_bayes import EmailNaiveBayes
from .log_regression import EmailLogisticRegression

class EmailClassifier:
    def __init__(self):
        self.decision_tree = EmailDecisionTree()
        self.naive_bayes = EmailNaiveBayes()
        self.log_regression = EmailLogisticRegression()
        
        # Pondérations pour chaque modèle
        self.weights = {
            "decision_tree": 0.4,
            "naive_bayes": 0.3,
            "logistic_regression": 0.3
        }
        
        # Charger les données d'entraînement si disponibles
        self._load_initial_data()

    def _load_initial_data(self):
        try:
            data_path = os.path.join(os.path.dirname(__file__), '../data/training_data.json')
            if os.path.exists(data_path):
                with open(data_path, 'r') as f:
                    data = json.load(f)
                    if 'emails' in data and len(data['emails']) > 0:
                        self.train(data['emails'])
                        print(f"Loaded and trained with {len(data['emails'])} email samples")
        except Exception as e:
            print(f"Error loading initial training data: {e}")


    def update_model_weights(self):
        """Met à jour les poids des modèles en fonction de leurs performances récentes"""
        if not hasattr(self, 'training_data') or len(self.training_data) < 5:
            # Ne pas mettre à jour les poids avec trop peu de données
            return self.weights
        
        # Obtenir les performances d'évaluation
        evaluation = self.evaluate()
        scores = evaluation["scores"]
        
        # Calculer les scores composites (moyenne des scores de catégorie et priorité)
        composite_scores = {}
        for model, metrics in scores.items():
            cat_score = metrics["category_score"]
            pri_score = metrics["priority_score"]
            # Moyenne des deux scores avec une légère préférence pour la catégorie (60/40)
            composite_scores[model] = 0.6 * cat_score + 0.4 * pri_score
        
        # Normaliser les scores pour obtenir des poids
        total_score = sum(composite_scores.values())
        if total_score > 0:
            # Appliquer un facteur d'inertie pour éviter des changements trop brusques
            inertia = 0.7  # 70% du poids précédent est conservé
            
            new_weights = {}
            for model, score in composite_scores.items():
                # Mélange de l'ancien poids (avec inertie) et du nouveau poids basé sur la performance
                normalized_score = score / total_score if total_score > 0 else 1.0 / len(composite_scores)
                new_weights[model] = inertia * self.weights.get(model, 0.3) + (1 - inertia) * normalized_score
            
            # Normaliser à nouveau pour s'assurer que la somme est égale à 1
            weight_sum = sum(new_weights.values())
            if weight_sum > 0:
                self.weights = {model: weight/weight_sum for model, weight in new_weights.items()}
                
            print(f"Poids mis à jour: {self.weights}")
            return self.weights
        return self.weights

    def train(self, emails):
        # Stocker les données pour l'évaluation future
        self.training_data = emails  # Conserver les données d'entraînement
        
        dt_result = self.decision_tree.train(emails)
        nb_result = self.naive_bayes.train(emails)
        lr_result = self.log_regression.train(emails)
        
        # Stocker les résultats de performance
        self.last_training_performance = {
            "decision_tree": dt_result["performance"],
            "naive_bayes": nb_result["performance"],
            "logistic_regression": lr_result["performance"]
        }
        
        # Mettre à jour les poids des modèles en fonction des performances
        self.update_model_weights()
        
        return {
            "num_samples": dt_result["num_samples"],
            "performance": self.last_training_performance,
            "model_weights": self.weights
        }


    def evaluate(self):
        """Évalue les performances des modèles sur les données d'entraînement"""
        if not hasattr(self, 'training_data') or not self.training_data:
            return {
                "message": "Aucune donnée d'entraînement disponible pour l'évaluation",
                "scores": {}
            }
        
        # Pour chaque exemple, comparer la prédiction avec la valeur réelle
        category_correct = {"decision_tree": 0, "naive_bayes": 0, "logistic_regression": 0}
        priority_correct = {"decision_tree": 0, "naive_bayes": 0, "logistic_regression": 0}
        total = len(self.training_data)
        
        for email in self.training_data:
            subject = email.get('subject', '')
            body = email.get('body', '')
            expected_category = email.get('category', '')
            expected_priority = email.get('priority', '')
            
            # Decision Tree
            dt_result = self.decision_tree.classify(subject, body)
            if dt_result['category'] == expected_category:
                category_correct['decision_tree'] += 1
            if dt_result['priority'] == expected_priority:
                priority_correct['decision_tree'] += 1
            
            # Naive Bayes
            nb_result = self.naive_bayes.classify(subject, body)
            if nb_result['category'] == expected_category:
                category_correct['naive_bayes'] += 1
            if nb_result['priority'] == expected_priority:
                priority_correct['naive_bayes'] += 1
            
            # Logistic Regression
            lr_result = self.log_regression.classify(subject, body)
            if lr_result['category'] == expected_category:
                category_correct['logistic_regression'] += 1
            if lr_result['priority'] == expected_priority:
                priority_correct['logistic_regression'] += 1
        
        # Calculer les précisions
        results = {}
        for model in ['decision_tree', 'naive_bayes', 'logistic_regression']:
            cat_accuracy = round(category_correct[model] / total, 3) if total > 0 else 0
            pri_accuracy = round(priority_correct[model] / total, 3) if total > 0 else 0
            
            results[model] = {
                "category_score": cat_accuracy,
                "priority_score": pri_accuracy
            }
        
        return {
            "message": f"Évaluation effectuée sur {total} exemples d'entraînement",
            "scores": results
        }


    def classify(self, subject, body):
        # Obtenir les prédictions de chaque modèle
        dt_result = self.decision_tree.classify(subject, body)
        nb_result = self.naive_bayes.classify(subject, body)
        lr_result = self.log_regression.classify(subject, body)
        
        # Obtenir toutes les catégories possibles à partir des résultats
        all_categories = set([dt_result["category"], nb_result["category"], lr_result["category"]])
        all_priorities = set([dt_result["priority"], nb_result["priority"], lr_result["priority"]])
        
        # Initialiser les scores
        category_scores = {cat: 0 for cat in all_categories}
        priority_scores = {pri: 0 for pri in all_priorities}
        
        # Pondérer les prédictions en fonction des poids des modèles
        for model, result, weight in [
            ("decision_tree", dt_result, self.weights["decision_tree"]),
            ("naive_bayes", nb_result, self.weights["naive_bayes"]),
            ("logistic_regression", lr_result, self.weights["logistic_regression"])
        ]:
            # Attribuer le score pondéré par la confiance et le poids du modèle
            category_scores[result["category"]] += result["confidence"] * weight
            priority_scores[result["priority"]] += result["confidence"] * weight
        
        # Sélectionner la catégorie et la priorité avec les scores les plus élevés
        final_category = max(category_scores.items(), key=lambda x: x[1])[0]
        final_priority = max(priority_scores.items(), key=lambda x: x[1])[0]
        
        # Calculer la confiance moyenne pondérée
        weighted_confidence = (
            dt_result["confidence"] * self.weights["decision_tree"] +
            nb_result["confidence"] * self.weights["naive_bayes"] +
            lr_result["confidence"] * self.weights["logistic_regression"]
        ) / sum(self.weights.values())
        
        return {
            "category": final_category,
            "priority": final_priority,
            "confidence": weighted_confidence,
            "model_weights": self.weights,  # Inclure les poids actuels des modèles
            "model_results": {
                "decision_tree": dt_result,
                "naive_bayes": nb_result,
                "logistic_regression": lr_result
            }
        }
