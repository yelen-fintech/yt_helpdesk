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

# build the container
`docker build -t email-classifier:latest .`

# delete the container
`docker rm my-classifier-cli`

# run the container
`docker run -it --name my-classifier-cli email-classifier:latest`


# build for prod
`MIX_ENV=prod mix release`

# test
`ImapApiClient.Classifier.Model.classify_email(" Bonjour, mon compte est bloqué. Pouvez-vous m'aider à le débloquer ? ")`

# run in daemon

`./_build/prod/rel/imap_api_client/bin/imap_api_client daemon`

# start
`_build/prod/rel/imap_api_client/bin/imap_api_client start`

# stop
`   _build/prod/rel/imap_api_client/bin/imap_api_client stop`
# chekc if running
`ps aux | grep imap_api_client`
