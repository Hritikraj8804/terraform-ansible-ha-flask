from flask import Flask
import socket

app = Flask(__name__)

@app.route('/')
def hello_world():
    # Show the hostname to prove which server/AZ responded
    hostname = socket.gethostname()
    return f"<h1>HA Flask App Live!</h1><h2>Server: {hostname}</h2><p>This deployment is highly available across multiple zones.</p>"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)
