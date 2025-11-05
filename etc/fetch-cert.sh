#!/bin/sh

payload=/etc/ssl/private/porkbun-keys.json
endpoint=https://api.porkbun.com/api/json/v3/ssl/retrieve/blip.town

/usr/local/bin/curl -s -X POST -d @$payload $endpoint  | /usr/local/bin/jq -r .certificatechain
