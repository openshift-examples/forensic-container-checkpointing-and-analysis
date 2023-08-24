#!/usr/bin/python3

import os
import http.server

counter = 0
secret_key = "EMPTY_KEY"


class handler(http.server.BaseHTTPRequestHandler):
    def do_GET(s):
        global counter
        s.send_response(200)
        s.send_header('Content-type', 'text/html')
        s.end_headers()
        if s.path.startswith('/create'):
            filename = s.path.split('?')
            if len(filename) != 2:
                s.wfile.write(b'usage error\n')
                return
            if '/' in filename[1]:
                s.wfile.write(b'usage error\n')
                return
            with open(filename[1], mode='w') as file:
                file.write(filename[1])
        if s.path.startswith('/secret'):
            secret = s.path.split('?')
            if len(secret) != 2:
                s.wfile.write(b'usage error\n')
                return
            global secret_key
            secret_key = secret[1]
        if os.path.exists('/data/prefix'):
            with open('/data/prefix', 'rb') as prefix:
                s.wfile.write(prefix.read())
        s.wfile.write(b'counter: %d\n' % counter)
        counter += 1


server = http.server.HTTPServer(('', 8080), handler)
server.serve_forever()