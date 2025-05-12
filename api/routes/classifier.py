import os
import json 
from flask import Blueprint, request, jsonify
from models.ensemble import EmailClassifier


classifier_blueprint = Blueprint('classifier', __name__)
email_classifier = EmailClassifier()

@classifier_blueprint.route('/classify', methods=['POST'])
def classify_email():
    data = request.json
    
    if not data or 'subject' not in data or 'body' not in data:
        return jsonify({
            'error': 'Les champs subject et body sont requis'
        }), 400
    
    subject = data['subject']
    body = data['body']
    
    classification = email_classifier.classify(subject, body)
    
    return jsonify({
        'category': classification['category'],
        'priority': classification['priority'],
        'confidence': classification['confidence']
    })

@classifier_blueprint.route('/train', methods=['POST', 'GET'])
def train_model():
    # Charger directement les données initiales du fichier
    try:
        data_path = os.path.join(os.path.dirname(__file__), '../data/training_data.json')
        if os.path.exists(data_path):
            with open(data_path, 'r') as f:
                data = json.load(f)
                if 'emails' in data and len(data['emails']) > 0:
                    result = email_classifier.train(data['emails'])
                    return jsonify({
                        'status': 'success',
                        'message': f'Modèle entraîné avec {result["num_samples"]} emails',
                        'performance': result['performance']
                    })
                else:
                    return jsonify({
                        'error': 'Aucun email trouvé dans le fichier de données'
                    }), 400
        else:
            return jsonify({
                'error': 'Fichier de données introuvable'
            }), 404
    except Exception as e:
        return jsonify({
            'error': f'Erreur lors du chargement des données: {str(e)}'
        }), 500

@classifier_blueprint.route('/evaluate', methods=['GET'])
def evaluate_models():
    """Endpoint pour évaluer les performances des modèles entraînés"""
    try:
        if hasattr(email_classifier, 'evaluate'):
            evaluation = email_classifier.evaluate()
            return jsonify({
                'status': 'success',
                'message': 'Évaluation des modèles effectuée',
                'performance': evaluation
            })
        else:
            # Si la méthode evaluate n'existe pas, essayer de récupérer les performances du dernier entraînement
            if hasattr(email_classifier, 'last_training_performance'):
                return jsonify({
                    'status': 'success',
                    'message': 'Récupération des performances du dernier entraînement',
                    'performance': email_classifier.last_training_performance
                })
            else:
                return jsonify({
                    'status': 'warning',
                    'message': 'Aucune méthode d\'évaluation disponible et pas de performances stockées'
                })
    except Exception as e:
        return jsonify({
            'error': f'Erreur lors de l\'évaluation : {str(e)}'
        }), 500

@classifier_blueprint.route('/test', methods=['GET'])
def test_prediction():
    """Endpoint pour tester des prédictions sur des exemples prédéfinis"""
    test_examples = [
        {
            "subject": "Demande de support technique urgent",
            "body": "Bonjour, notre système est en panne depuis ce matin. Nous ne pouvons pas traiter les commandes de nos clients. Pouvez-vous intervenir au plus vite ?"
        },
        {
            "subject": "Renseignement sur vos produits",
            "body": "Bonjour, je suis intéressé par vos services et j'aimerais obtenir plus d'informations sur vos tarifs. Merci d'avance pour votre réponse."
        },
        {
            "subject": "URGENT: Bug critique en production",
            "body": "L'application principale est inaccessible et tous nos clients sont impactés. Nous perdons des milliers d'euros chaque heure. Une intervention immédiate est requise!"
        },
        {
            "subject": "Meeting next week",
            "body": "Hello team, I would like to schedule a meeting next week to discuss our new project. Please let me know your availability. Best regards."
        }
    ]
    
    results = []
    for example in test_examples:
        classification = email_classifier.classify(example['subject'], example['body'])
        results.append({
            'example': example,
            'classification': classification
        })
    
    return jsonify({
        'status': 'success',
        'message': 'Tests de prédiction effectués',
        'results': results
    })

@classifier_blueprint.route('/test-custom', methods=['POST'])
def test_custom_email():
    """Endpoint pour tester la classification sur un email personnalisé"""
    try:
        data = request.json
        if not data or 'subject' not in data or 'body' not in data:
            return jsonify({
                'error': 'Les champs "subject" et "body" sont requis'
            }), 400
        
        classification = email_classifier.classify(data['subject'], data['body'])
        
        return jsonify({
            'status': 'success',
            'message': 'Classification effectuée',
            'input': {
                'subject': data['subject'],
                'body': data['body']
            },
            'classification': classification
        })
    except Exception as e:
        return jsonify({
            'error': f'Erreur lors de la classification : {str(e)}'
        }), 500
