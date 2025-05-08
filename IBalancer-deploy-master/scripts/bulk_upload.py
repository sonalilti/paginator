#!/usr/bin/env python3

import argparse
import sys, os, io
import json, copy
import mimetypes, uuid
import hashlib
from urllib import request
from zipfile import ZipFile
from multiprocessing import Pool

class MultiPartForm:
    """Accumulate the data to be used when posting a form."""

    def __init__(self):
        self.form_fields = []
        self.files = []
        # Use a large random byte string to separate
        # parts of the MIME data.
        self.boundary = uuid.uuid4().hex.encode('utf-8')
        return

    def get_content_type(self):
        return 'multipart/form-data; boundary={}'.format(
            self.boundary.decode('utf-8'))

    def add_field(self, name, value):
        """Add a simple field to the form data."""
        self.form_fields.append((name, value))

    def add_file(self, fieldname, filename, fileHandle,
                 mimetype=None):
        """Add a file to be uploaded."""
        body = fileHandle.read()
        if mimetype is None:
            mimetype = (
                mimetypes.guess_type(filename)[0] or
                'application/octet-stream'
            )
        self.files.append((fieldname, filename, mimetype, body))
        return

    @staticmethod
    def _form_data(name):
        return ('Content-Disposition: form-data; '
                'name="{}"\r\n').format(name).encode('utf-8')

    @staticmethod
    def _attached_file(name, filename):
        return ('Content-Disposition: file; '
                'name="{}"; filename="{}"\r\n').format(
                    name, filename).encode('utf-8')

    @staticmethod
    def _content_type(ct):
        return 'Content-Type: {}\r\n'.format(ct).encode('utf-8')

    def __bytes__(self):
        """Return a byte-string representing the form data,
        including attached files.
        """
        buffer = io.BytesIO()
        boundary = b'--' + self.boundary + b'\r\n'

        # Add the form fields
        for name, value in self.form_fields:
            buffer.write(boundary)
            buffer.write(self._form_data(name))
            buffer.write(b'\r\n')
            buffer.write(value.encode('utf-8'))
            buffer.write(b'\r\n')

        # Add the files to upload
        for f_name, filename, f_content_type, body in self.files:
            buffer.write(boundary)
            buffer.write(self._attached_file(f_name, filename))
            buffer.write(self._content_type(f_content_type))
            buffer.write(b'\r\n')
            buffer.write(body)
            buffer.write(b'\r\n')

        buffer.write(b'--' + self.boundary + b'--\r\n')
        return buffer.getvalue()

def parse_arguments():
  if 'NUCLEUS_ADMIN_URI' in os.environ:
    admin_uri = { 'default': os.environ['NUCLEUS_ADMIN_URI'] }
  else:
    admin_uri = { 'required': True }

  if 'NUCLEUS_API_KEY' in os.environ:
    api_key = { 'default': os.environ['NUCLEUS_API_KEY'] }
  else:
    api_key = { 'required': True }

  parser = argparse.ArgumentParser()
  parser.add_argument("directory",
        help="Directory where to look for template subdirectories")
  parser.add_argument("-b", "--backend",
        help="Nucleus Admin URI. Use parameter or set NUCLEUS_ADMIN_URI environment variable.",
        **admin_uri)
  parser.add_argument("-k", "--api-key",
        help="API key. Use parameter or set NUCLEUS_API_KEY environment variable.",
        **api_key)
  parser.add_argument("-t", "--tmp-dir",
        help="Where to keep temporary files, default value is '/tmp'",
        default='/tmp')
  parser.add_argument("-s", "--state-dir",
        help="Where to store state file, default value is '/var/tmp'",
        default='/var/tmp')
  global args
  args = parser.parse_args()

def get_session_token():
  baseurl = args.backend.rstrip('/')
  sys.stdout.write ('\nRequesting session token from '+baseurl+': ')
  sys.stdout.flush()
  if baseurl[0:7] == 'http://' or baseurl[0:8] == 'https://':
    api_url = baseurl+'/api/v1/session/start/'
    template_ul = baseurl+'/api/v1/entity/templates'
    try:
      st_offer_raw = request.urlopen(api_url+args.api_key)
    except Exception as e:
      print(('Could not get session key via'+api_url+': '+str(e)))
      sys.exit(1)
  else:
    api_url = 'https://'+baseurl+'/api/v1/session/start/'
    template_ul = 'https://'+baseurl+'/api/v1/entity/templates'
    try:
      st_offer_raw = request.urlopen(api_url+args.api_key)
    except:
      api_url = 'http://'+baseurl+'/api/v1/session/start/'
      template_ul = 'http://'+baseurl+'/api/v1/entity/templates'
      try:
        st_offer_raw = request.urlopen(api_url+args.api_key)
      except Exception as e:
        print(('Could not get session key from '+api_url+', both via http:// and https:// : '+str(e)))
        sys.exit(1)
  st_offer_bdy = st_offer_raw.read()
  st_offer_obj = json.loads(st_offer_bdy)

  global session_token
  global template_endpoint
  if st_offer_obj['success'] == 1:
    session_token = st_offer_obj['token']
    template_endpoint = template_ul
    print ('Success!\n')
  else:
    print ('Failure:\n')
    print((json.dumps(st_offer_obj, sort_keys=True, indent=4, separators=(',', ': '))))
    sys.exit(1)

def send_template(template):
  archive = args.tmp_dir.rstrip('/')+'/'+os.path.basename(template)+'.zip'
  with ZipFile(archive, mode='w', compression=8) as ztmp:
    for root, dirs, files in os.walk(template):
      for file in files:
        filename = os.path.join(root,file)
        ztmp.write(filename, filename[len(template)+1:])
  form = MultiPartForm()
  form.add_field('name', os.path.basename(template))
  form.add_field('token', session_token)
  form.add_file('archive', os.path.basename(template)+'.zip', fileHandle=io.open(archive, mode="rb"))
  data = bytes(form)
  try:
    r = request.Request(template_endpoint, data=data)
    r.add_header('User-agent', 'Nucleus Bulk Upload Script bulk_upload.py', )
    r.add_header('Content-type', form.get_content_type())
    r.add_header('Content-length', len(data))
    response = json.loads(request.urlopen(r).read().decode('utf-8'))
    response['template'] = template
  except Exception as e:
    response = json.loads('{ "success": 0, "message": "'+e.message+'", "template":'+template+' }')
  del form
  os.remove (archive)
  return json.dumps(response)


if __name__ == '__main__':
  parse_arguments()
  get_session_token()

  statefile_path = ( args.state_dir + '/.nucleus_bulk_upload.' +
                   hashlib.md5(args.directory.encode('utf-8')).hexdigest() +
                   '.state' )

  try:
    with open(statefile_path, 'r') as statefile:
        templates = json.load(statefile)
  except:
    templates = json.loads('{"dirs": []}')

  if 'dirs' in templates and len(templates['dirs']) > 0:
    print ('Resuming from state file ' + statefile_path +',')
    print ('uploading contents of '+args.directory.rstrip('/')+' directory:')
  else:
    print ('Working on contents of '+args.directory.rstrip('/')+' directory:')
    try:
        dirs = os.listdir(args.directory)
    except Exception as e:
        print(('Could not get directory listing: '+str(e)))
        sys.exit(1)
    for dir in dirs:
        if dir not in ['__MACOSX'] and dir[0] != '.':
            templates['dirs'].append(args.directory.rstrip('/')+'/'+dir)

  try:
    with open(statefile_path, 'w') as statefile:
        json.dump(templates, statefile)
  except Exception as e:
    print(('Could not open state file for writing: '+str(e)))
    sys.exit(1)

  dirs = copy.deepcopy(templates['dirs'])

  with Pool(6) as p:
    it = p.imap_unordered(send_template, dirs)
    for x in it:
      response = json.loads(x)
      if response['success'] == 1:
        templates['dirs'].remove(response['template'])
        print(response['template']+': OK')
        with open(statefile_path, 'w') as statefile:
          json.dump(templates, statefile)
      else:
        try:
          print(response['template']+': Fail')
          print(' -> '+response['message'])
        except:
          print(response)
