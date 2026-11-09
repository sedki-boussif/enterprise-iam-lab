import os
from functools import wraps
from flask import Flask, session, redirect, url_for, abort
from markupsafe import escape
from authlib.integrations.flask_client import OAuth

app = Flask(__name__)
app.secret_key = os.environ['APP_SECRET']

KC = os.environ.get('KC_INTERNAL_URL', 'http://keycloak:8080')

oauth = OAuth(app)
oauth.register(
    name='keycloak',
    client_id='webapp',
    client_secret=os.environ['KC_CLIENT_SECRET'],
    server_metadata_url=KC + '/realms/company/.well-known/openid-configuration',
    client_kwargs={'scope': 'openid profile email'},
)

def need(group=None):
    def deco(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            user = session.get('user')
            if not user:
                return redirect(url_for('login'))
            if group and group not in user.get('groups', []):
                abort(403)
            return fn(*args, **kwargs)
        return wrapper
    return deco

@app.route('/')
def home():
    user = session.get('user')
    if not user:
        return '<a href=/login>Log in with company SSO</a>'
    name = escape(user.get('preferred_username', '?'))
    groups = escape(', '.join(user.get('groups', [])))
    return f'Hello {name}. Groups: {groups}'

@app.route('/login')
def login():
    return oauth.keycloak.authorize_redirect(url_for('callback', _external=True))

@app.route('/callback')
def callback():
    token = oauth.keycloak.authorize_access_token()
    session['user'] = token['userinfo']
    return redirect('/')

@app.route('/profile')
@need()
def profile():
    return 'Employee page: ' + str(escape(session['user']))

@app.route('/hr')
@need('GG-HR')
def hr():
    return 'HR page: employee records'

@app.route('/admin')
@need('GG-Admins')
def admin():
    return 'Admin page: manage users and permissions'

@app.route('/logout')
def logout():
    session.clear()
    return redirect('/')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
