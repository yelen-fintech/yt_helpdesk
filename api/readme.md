# create virtual environnement
`uv venv`

# load the virtual environnment
`source .venv/bin/activate`

# install required librairies
`uv pip install -r requirements.txt`

# run the app
`uv run app.py`

# test
# français :

`curl -X POST http://localhost:5000/classify \
  -H "Content-Type: application/json" \
  -d "{
      \"subject\": \"Problème de connexion urgent\",
      \"body\": \"Je ne peux plus me connecter à mon compte depuis ce matin. J'ai besoin d'aide rapidement car j'ai une réunion importante.\"
  }"
`

# entrainer 

`curl http://localhost:5000/train`


# évaluer les modèles (après l'entraînement) :

`curl http://localhost:5000/evaluate`

# tester les prédictions sur des exemples prédéfinis (incluant un exemple en anglais) :

`curl http://localhost:5000/test`

# tester la classification sur un email personnalisé :

`curl -X POST http://localhost:5000/test-custom \
  -H "Content-Type: application/json" \
  -d '{"subject":"Question sur facturation", "body":"Bonjour, je n ai pas reçu ma facture du mois dernier. Pouvez-vous me l envoyer? Merci."}'`