# Utiliser l'image officielle Python comme base
FROM python:3.11-slim

# Variables d'environnement
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Créer un répertoire de travail
WORKDIR /app

# Mettre à jour pip
RUN pip install --upgrade pip

# Copier les fichiers de dépendances
COPY requirements.txt .

# Installer les dépendances directement avec pip
RUN pip install -r requirements.txt

# Copier le code source
COPY . .

# Ouvrir le port sur lequel l'application s'exécutera
EXPOSE 5000

# Commande pour exécuter l'application
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]