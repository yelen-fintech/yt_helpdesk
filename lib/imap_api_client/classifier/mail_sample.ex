defmodule ImapApiClient.Classifier.MailSample do
 @moduledoc """
  Collection d'exemples d'emails avec catégories redéfinies pour plus de clarté
  et une meilleure distinction des intentions.
  """

def get_sample_mails do
  [
    # ================ SPAM ================
    %{
      text: "URGENT: Votre compte sera bloqué dans 24h. Cliquez sur ce lien pour éviter la suspension: http://bit.ly/1234",
      expected: "spam",
      urgency: "low" # Urgence fabriquée par le spammeur, pas une vraie urgence pour le destinataire
    },
    %{
      text: "Félicitations! Vous avez gagné un iPhone 15 Pro! Cliquez ici pour réclamer votre prix: http://claim-prize.com",
      expected: "spam",
      urgency: "low"
    },
    %{
      text: "ALERTE DE SÉCURITÉ: Nous avons détecté un accès non autorisé à votre compte. Vérifiez immédiatement: http://secure-verify.net",
      expected: "spam", # Phishing se faisant passer pour une alerte
      urgency: "medium" # Peut générer une inquiétude plus élevée
    },
    %{
      text: "FACTURE EN SOUFFRANCE: Votre facture N°INV-2024-789 est impayée. Réglez avant le 15/05 pour éviter les pénalités: http://pay-now.biz",
      expected: "spam", # Fausse facture
      urgency: "medium"
    },
    %{
      text: "OPPORTUNITÉ D'INVESTISSEMENT UNIQUE: Gagnez 500% en 24h avec notre nouvelle crypto-monnaie! Places limitées: http://crypto-gold.io",
      expected: "spam",
      urgency: "low"
    },
    %{
      text: "Confirmation de votre commande Amazon que vous n'avez pas passée. Voir les détails: http://amazon-confirm.com/details",
      expected: "spam", # Phishing
      urgency: "medium"
    },

    # ================ PROMOTIONS / MARKETING ================
    %{
      text: "RÉDUCTION EXCEPTIONNELLE: -50% sur toute notre collection été! Offre valable jusqu'à dimanche seulement.",
      expected: "promotions_marketing",
      urgency: "low"
    },
    %{
      text: "DERNIER JOUR! Notre promotion spéciale fin d'année se termine ce soir à minuit. Profitez de -70% sur les frais de transfert!",
      expected: "promotions_marketing",
      urgency: "high"
    },
    %{
      text: "Newsletter de Mai: Découvrez nos nouvelles fonctionnalités et nos conseils d'experts.",
      expected: "promotions_marketing", # Newsletter est du marketing de contenu
      urgency: "low"
    },
    %{
      text: "Webinaire exclusif: Apprenez à optimiser vos finances personnelles avec nos experts. Inscrivez-vous gratuitement!",
      expected: "promotions_marketing",
      urgency: "low"
    },
    %{
      text: "Vous avez des points fidélité qui expirent bientôt! Utilisez-les avant le 30 pour obtenir une réduction.",
      expected: "promotions_marketing",
      urgency: "medium" # Implique une action pour ne pas perdre quelque chose
    },
    %{
      text: "Nouveau produit ! Découvrez notre carte de crédit premium avec 0% de frais la première année.",
      expected: "promotions_marketing",
      urgency: "low"
    },

    # ================ PERSONNEL ================
    %{
      text: "Salut ! On se retrouve toujours ce weekend pour l'anniversaire de Julie ? N'oublie pas d'apporter le cadeau !",
      expected: "personnel",
      urgency: "low"
    },
    %{
      text: "URGENT: Ma voiture est tombée en panne et je suis coincé à 30km de chez moi. Peux-tu venir me chercher ou m'aider à trouver une solution?",
      expected: "personnel",
      urgency: "high"
    },
    %{
      text: "Coucou, tu as des nouvelles pour le film de ce soir? On maintient ou on décale?",
      expected: "personnel",
      urgency: "low"
    },
    %{
      text: "Je suis vraiment désolé, mais je ne pourrai pas être là pour ton déménagement samedi. Un imprévu de dernière minute.",
      expected: "personnel",
      urgency: "medium" # Informatif mais peut impacter les plans de l'autre
    },
    %{
      text: "Photos de vacances enfin en ligne! Le lien: https://photos.example.com/vacances2024",
      expected: "personnel",
      urgency: "low"
    },

    # ================ PROFESSIONNEL / INTERNE ================
    %{
      text: "Bonjour Jean, j'espère que vous allez bien. Pourriez-vous m'envoyer le rapport financier avant jeudi ? Cordialement, Marie",
      expected: "professionnel_interne",
      urgency: "medium"
    },
    %{
      text: "URGENT: Nous avons identifié une erreur dans le contrat client X envoyé hier. Veuillez ne pas le signer et attendre la version corrigée.",
      expected: "professionnel_interne",
      urgency: "high"
    },
    %{ # Ancien "Urgent"
      text: "ALERTE SÉCURITÉ INTERNE: Nous avons détecté une tentative d'intrusion sur nos serveurs. Veuillez changer immédiatement vos mots de passe professionnels.",
      expected: "professionnel_interne", # Notification interne critique
      urgency: "high"
    },
    %{ # Ancien "Urgent"
      text: "Important: Le déploiement prévu ce soir est reporté suite à un problème critique identifié en pré-production. Standby pour plus d'informations.",
      expected: "professionnel_interne", # Information interne opérationnelle
      urgency: "medium"
    },
    %{ # Ancien "Urgent"
      text: "URGENT: Réunion de crise à 15h aujourd'hui en salle de conférence. Présence obligatoire de toute l'équipe projet Alpha.",
      expected: "professionnel_interne", # Convocation interne
      urgency: "high"
    },
    %{
      text: "Rappel: Formation obligatoire sur la nouvelle politique de sécurité demain à 10h en salle B2.",
      expected: "professionnel_interne",
      urgency: "medium"
    },
    %{
      text: "PV de la réunion d'équipe du 13/05 en pièce jointe. Merci de valider vos actions avant vendredi.",
      expected: "professionnel_interne",
      urgency: "low"
    },

    # ================ SUPPORT CLIENT ================
    # (Problèmes, difficultés, besoin d'une action du service client)
    %{
      text: "Je n'arrive pas à me connecter à mon compte depuis ce matin, message d'erreur 'Utilisateur inconnu'. J'ai besoin d'accéder à mes fonds urgemment.",
      expected: "support_client",
      urgency: "high"
    },
    %{
      text: "Bonjour, j'ai fait un virement de 2000€ hier qui n'apparaît nulle part. Pouvez-vous vérifier et le localiser? Référence: VIR20240514-8976.",
      expected: "support_client",
      urgency: "high"
    },
    %{ # Ancien "Fonctionnalités" (bug)
      text: "La fonction de paiement par QR code ne fonctionne plus depuis la dernière mise à jour de l'application. Tous nos vendeurs sont impactés!",
      expected: "support_client", # Un bug bloquant est une demande de support
      urgency: "high"
    },
    %{ # Ancien "Fonctionnalités" (difficulté d'usage)
      text: "Je ne trouve plus l'option pour créer des règles de catégorisation automatique des transactions. A-t-elle été déplacée ou supprimée?",
      expected: "support_client", # L'utilisateur est perdu, a besoin d'aide
      urgency: "medium"
    },
    %{
      text: "J'ai été débité deux fois pour la même transaction (ref: TX-85421). Pouvez-vous annuler le doublon et me rembourser s'il vous plaît?",
      expected: "support_client",
      urgency: "high"
    },
    %{
      text: "L'application mobile se ferme toute seule quand j'essaie d'ajouter un bénéficiaire. C'est très frustrant.",
      expected: "support_client",
      urgency: "medium"
    },
    %{
      text: "Bjr, g pa reçu le code de securiter pr valider mon paiment de 500€. C urgent svp!!!", # Style informel
      expected: "support_client",
      urgency: "high"
    },
    %{
      text: "Mon virement international vers les USA est bloqué depuis 3 jours. J'ai besoin que ce soit résolu rapidement, mon fournisseur attend.",
      expected: "support_client",
      urgency: "high"
    },
    %{
      text: "Je ne comprends pas pourquoi des frais de 5€ m'ont été prélevés ce mois-ci. Pouvez-vous m'expliquer?",
      expected: "support_client",
      urgency: "medium"
    },
    %{
      text: "Impossible de télécharger mon relevé de compte en PDF, le site affiche une erreur 500.",
      expected: "support_client",
      urgency: "medium"
    },
    %{
      text: "Aide!! J'ai oublié mon mot de passe et je ne reçois pas l'email de réinitialisation. J'ai vérifié mes spams.",
      expected: "support_client",
      urgency: "high"
    },

    # ================ DEMANDE D'INFORMATION / QUESTION ================
    # (Questions générales, curiosité, pas de problème signalé)
    %{
      text: "Bonjour, j'aimerais savoir si votre service premium inclut des alertes SMS pour les transactions importantes.",
      expected: "demande_information_question",
      urgency: "low"
    },
    %{
      text: "Quelles sont les limites de montant pour les virements instantanés avec un compte standard?",
      expected: "demande_information_question",
      urgency: "low"
    },
    %{ # Ancien "Fonctionnalités" (question d'usage)
      text: "Comment puis-je configurer des notifications push pour chaque transaction entrante/sortante sur l'application mobile?",
      expected: "demande_information_question", # Demande comment faire, pas un bug
      urgency: "medium" # L'utilisateur a un besoin clair mais pas bloquant
    },
    %{
      text: "Votre service est-il compatible avec les paiements par Apple Pay?",
      expected: "demande_information_question",
      urgency: "low"
    },
    %{
      text: "Quels sont les frais pour un retrait d'argent à l'étranger hors zone Euro?",
      expected: "demande_information_question",
      urgency: "low"
    },
    %{
      text: "Est-il possible de clôturer mon compte épargne directement depuis l'application mobile?",
      expected: "demande_information_question",
      urgency: "low"
    },
    %{
      text: "Quels sont les documents nécessaires pour ouvrir un compte joint?",
      expected: "demande_information_question",
      urgency: "low"
    },
    %{
      text: "Proposez-vous des solutions de crédit immobilier? Si oui, où puis-je trouver les taux actuels?",
      expected: "demande_information_question",
      urgency: "low"
    },


    # ================ FEEDBACK / SUGGESTION ================
    # (Avis, idées d'amélioration, retours d'expérience)
    %{
      text: "J'adore votre nouvelle interface, elle est beaucoup plus claire! Excellent travail.",
      expected: "feedback_suggestion",
      urgency: "low"
    },
    %{
      text: "Ce serait vraiment utile si on pouvait exporter les relevés au format QIF pour mon logiciel de compta. Vous pourriez ajouter ça?",
      expected: "feedback_suggestion",
      urgency: "low"
    },
    %{
      text: "Je trouve que le processus de vérification d'identité est un peu long et compliqué par rapport à vos concurrents.",
      expected: "feedback_suggestion", # Feedback négatif constructif
      urgency: "medium" # À prendre en compte sérieusement
    },
    %{
      text: "Vous devriez proposer un mode sombre pour l'application, ce serait plus reposant pour les yeux.",
      expected: "feedback_suggestion",
      urgency: "low"
    },
    %{
      text: "L'option de 'paiement rapide' est géniale, mais il manque la possibilité de sauvegarder plusieurs cartes pour différents usages.",
      expected: "feedback_suggestion",
      urgency: "low"
    },
    %{
      text: "La musique d'attente de votre service client est insupportable. Pensez à la changer!",
      expected: "feedback_suggestion", # Feedback négatif
      urgency: "low"
    },

    # ================ DOCUMENTATION ================
    # (Questions/problèmes *sur* la documentation elle-même)
    %{
      text: "La documentation API sur votre site contient des exemples de code pour l'endpoint /transfer qui ne fonctionnent pas. Notre intégration est bloquée.",
      expected: "documentation",
      urgency: "high" # Erreur critique dans la doc bloquant un tiers
    },
    %{
      text: "Bonjour, où puis-je trouver le guide complet sur la configuration des webhooks? Le lien dans la FAQ semble mort.",
      expected: "documentation",
      urgency: "medium"
    },
    %{
      text: "Je cherche les conditions générales de service (CGS) les plus récentes. Sont-elles disponibles en PDF sur votre site?",
      expected: "documentation", # Recherche d'un document spécifique
      urgency: "low"
    },
    %{
      text: "Le tutoriel vidéo pour l'intégration API est obsolète, il ne correspond plus à la version actuelle de l'interface.",
      expected: "documentation",
      urgency: "medium" # Peut causer confusion et perte de temps
    },
    %{
      text: "Pourriez-vous ajouter une section 'Dépannage commun' à la FAQ? Cela aiderait beaucoup.",
      expected: "documentation", # Suggestion d'amélioration de la doc
      urgency: "low"
    },

    # ================ CAS AMBIGUS ET MIXTES (revisités) ================
    # Le but est de choisir la catégorie la plus pertinente pour une *première action*
    %{
      text: "L'authentification à deux facteurs ne fonctionne pas avec mon nouveau téléphone. La doc dit de faire X, mais ça ne marche pas. Au secours!",
      expected: "support_client", # L'utilisateur est bloqué, c'est le point principal. La mention de la doc est secondaire.
      urgency: "high"
    },
    %{
      text: "Je ne trouve pas comment configurer les notifications par email. Cette fonctionnalité existe-t-elle ou y a-t-il une alternative? J'ai regardé dans la FAQ sans succès.",
      expected: "support_client", # "Je ne trouve pas" et "sans succès" suggère une difficulté > simple question.
                                  # Pourrait être "demande_information_question" si formulé plus neutrement ("Comment configurer X? Existe-t-il Y?").
      urgency: "medium"
    },
    %{
      text: "Bonjour, deux questions: 1) Comment augmenter mes plafonds de carte? C'est pour un achat urgent. 2) Votre documentation sur l'API est-elle à jour pour les virements récurrents?",
      expected: "support_client", # La question 1 est un besoin de support direct et urgent.
                                  # Un système avancé pourrait extraire 2 intentions.
      urgency: "high" # À cause de la Q1
    }
  ]
end
end
