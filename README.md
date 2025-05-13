# ImapApiClient
## Requirements

    Go to github and create a fine granded token to store in .env
    
    Go to the repository yt_helpdesk/settings activating issues

    Go to repository secrest and variables/actions and add the channels webhook links

## add librairies
`mix deps.get`

# build 
`mix compile`

# run
`iex -S mix` 

# test email 
`Classification.IntegrationTest.test_email_processing()`

# train model
`Classification.ModelTrainer.train_all()`

# build the container
`docker build -t email-classifier:latest .`

# delete the container
`docker rm my-classifier-cli`

# run the container
`docker run -it --name my-classifier-cli email-classifier:latest`
