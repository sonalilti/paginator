#!/usr/bin/env python3

import argparse
import sys, os
import json
import csv
import urllib
from urllib import request

if 'NUCLEUS_ADMIN_URI' in os.environ:
    admin_uri = { 'default': os.environ['NUCLEUS_ADMIN_URI'] }
else:
    admin_uri = { 'required': True }

if 'NUCLEUS_API_KEY' in os.environ:
    api_key = { 'default': os.environ['NUCLEUS_API_KEY'] }
else:
    api_key = { 'required': True }

parser = argparse.ArgumentParser()
parser.add_argument("csv_file",
        help="CSV file to parse")
parser.add_argument("-b", "--backend",
        help="Nucleus Admin URI. Use parameter or set NUCLEUS_ADMIN_URI environment variable.",
        **admin_uri)
parser.add_argument("-k", "--api-key",
        help="API key. Use parameter or set NUCLEUS_API_KEY environment variable.",
        **api_key)
parser.add_argument("-s", "--summary-file",
        help="Machine parseable log. By default it is placed next to CSV_FILE with the same basename and '-log.csv' postfix.")
args = parser.parse_args()

sys.stdout.write ('\nRequesting session token from '+args.backend+': ')
sys.stdout.flush()

if args.backend[0:7] == 'http://' or args.backend[0:8] == 'https://':
  try:
    baseurl = args.backend.rstrip('/')
    st_offer_raw = request.urlopen(baseurl+'/api/v1/session/start/'+args.api_key)
  except Exception as e:
    print('Could not get API key: '+str(e))
    sys.exit(1)
else:
  try:
    baseurl = 'https://'+args.backend.rstrip('/')
    st_offer_raw = request.urlopen(baseurl+'/api/v1/session/start/'+args.api_key)
  except urllib.error.HTTPError as e:
    baseurl = 'http://'+args.backend.rstrip('/')
    st_offer_raw = request.urlopen(baseurl+'/api/v1/session/start/'+args.api_key)
  except Exception as e:
    print('Could not get API key: '+str(e))
    sys.exit(1)

st_offer_bdy = st_offer_raw.read()
st_offer_obj = json.loads(st_offer_bdy)

if st_offer_obj['success'] == 1:
  session_token = st_offer_obj['token']
  print ('Success!\n')
else:
  print ('Failure:\n')
  print(json.dumps(st_offer_obj, sort_keys=True, indent=4, separators=(',', ': ')))
  sys.exit(1)

try:
  csvfile = open(args.csv_file, newline='')
  reader = csv.reader(csvfile)
except Exception as e:
  print('Could not load CSV file: '+str(e))
  sys.exit(1)

if not args.summary_file:
  args.summary_file = os.path.splitext(args.csv_file)[0]+'-log.csv'

try:
  sumfile = open(args.summary_file, 'w', newline='')
  logwriter = csv.writer(sumfile, quoting=csv.QUOTE_MINIMAL)
except Exception as e:
  print('Could not open `'+args.summary_file+'` for writing: '+str(e))
  sys.exit(1)

for row in reader:
  template = row[0]
  arguments = row[1].split('?')[1]
  sys.stdout.write (' '+template[0:13]+':	')
  sys.stdout.flush()
  tpl_test_req = ( baseurl   + '/api/v1/queue_by_template/' + template +
                   '?' + arguments + '&ids[info]=1&ids[key]=' +args.api_key )
  try:
    tpl_test_raw = request.urlopen(tpl_test_req)
  except urllib.error.HTTPError as e:
    error = str(e.read(), "utf-8")
    print('failed with code '+str(e.code)+', reason: `'+error+'`')
    logwriter.writerow([tpl_test_req, '', 'Error '+str(e.code)+': '+error])
  else:
    tpl_test_bdy = str(tpl_test_raw.read(), "utf-8")
    tpl_test_obj = json.loads(tpl_test_bdy)
    if tpl_test_obj['status'] == 200:
      timing = tpl_test_obj['timings'][0]['timing']
      print('done in '+str(timing)+' ms')
      logwriter.writerow([tpl_test_req, str(timing), 'ok'])

print('\nSummary has been saved to '+args.summary_file+'\n')
