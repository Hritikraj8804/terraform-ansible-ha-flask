from flask import Flask, request, jsonify
import socket
import random

app = Flask(__name__)

# Simple, shared state for the game (shared across all requests on THIS specific server)
# In a real app, this state would be in a database (like RDS).
GAME_STATE = {
    "location": "The Crossroads",
    "health": 100,
    "inventory": []
}

@app.route('/')
def home_screen():
    hostname = socket.gethostname()
    
    # Simple HTML layout for the game interface
    html = f"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <title>HA Adventure Game</title>
        <style>
            body {{ font-family: monospace; background-color: #0d1117; color: #c9d1d9; max-width: 800px; margin: 0 auto; padding: 20px; }}
            h1 {{ color: #58a6ff; border-bottom: 2px solid #21262d; padding-bottom: 10px; }}
            pre {{ background-color: #161b22; padding: 15px; border: 1px solid #30363d; overflow-x: auto; }}
            .info {{ margin-top: 20px; padding: 10px; border-left: 3px solid #8b949e; }}
        </style>
    </head>
    <body>
        <h1>HA Adventure Game: The Terraform Labyrinth</h1>
        
        <pre>
Welcome, adventurer!
You are at: {GAME_STATE['location']}
Your Health: {GAME_STATE['health']}
Server Hostname: {hostname} (from AZ: {socket.gethostbyname(hostname).split('.')[2]})
Your Inventory: {', '.join(GAME_STATE['inventory']) if GAME_STATE['inventory'] else 'Nothing'}
        
Available Commands:
/move?to=east
/move?to=west
/pickup
/health
        </pre>
        
        <div class="info">
            <strong>Deployment Status (V2):</strong> Running on a Highly Available (HA) {len(request.host.split('.'))} AZ cluster.
            <p>Hint: Try refreshing the page! Since there's no Load Balancer, your browser might hit the same server.</p>
        </div>
    </body>
    </html>
    """
    return html

@app.route('/move')
def move():
    direction = request.args.get('to', 'nowhere')
    if direction in ['east', 'west']:
        new_location = "The Eastern Jungle" if direction == 'east' else "The Western Caves"
        GAME_STATE['location'] = new_location
        return jsonify(message=f"You successfully moved {direction} to {new_location}. Health is {GAME_STATE['health']}.", status="success")
    return jsonify(message="Invalid move. Try /move?to=east or /move?to=west.", status="error")

@app.route('/pickup')
def pickup():
    item = random.choice(["Key", "Sword", "Shield", "Torch"])
    if item not in GAME_STATE['inventory']:
        GAME_STATE['inventory'].append(item)
        return jsonify(message=f"You found a {item} and added it to your inventory!", inventory=GAME_STATE['inventory'])
    return jsonify(message="The area is empty.", inventory=GAME_STATE['inventory'])

@app.route('/health')
def check_health():
    return jsonify(health=GAME_STATE['health'], location=GAME_STATE['location'])

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)
