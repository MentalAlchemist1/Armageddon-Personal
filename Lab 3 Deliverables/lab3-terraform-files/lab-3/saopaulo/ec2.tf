# ec2.tf
# São Paulo EC2 - Stateless compute that connects to Tokyo RDS via TGW

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# User data script to bootstrap the application
locals {
  user_data = <<-EOF
    #!/bin/bash
    set -ex
    
    # Update system
    dnf update -y
    
    # Install Python and dependencies
    dnf install -y python3-pip mariadb105
    pip3 install flask pymysql
    
    # Create application directory
    mkdir -p /opt/app
    cd /opt/app
    
    # Create the Flask application
    # NOTE: This app connects to TOKYO RDS via TGW - no local database exists
    cat > app.py << 'APPEOF'
    import os
    import pymysql
    from flask import Flask, request
    
    app = Flask(__name__)
    
    # Connection points to Tokyo RDS via TGW corridor
    DB_CONFIG = {
        "host": os.environ.get("DB_HOST"),
        "user": os.environ.get("DB_USER"),
        "password": os.environ.get("DB_PASS"),
        "database": os.environ.get("DB_NAME"),
        "port": int(os.environ.get("DB_PORT", 3306))
    }
    
    def get_connection():
        return pymysql.connect(**DB_CONFIG)
    
    @app.route('/health')
    def health():
        return 'OK', 200
    
    @app.route('/init')
    def init_db():
        try:
            conn = get_connection()
            cursor = conn.cursor()
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS notes (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    content VARCHAR(255),
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            ''')
            conn.commit()
            conn.close()
            return 'Database initialized (via TGW to Tokyo RDS)!', 200
        except Exception as e:
            print(f'ERROR: DB connection failed: {e}')
            return f'Error: {e}', 500
    
    @app.route('/add')
    def add_note():
        note = request.args.get('note', 'default note')
        try:
            conn = get_connection()
            cursor = conn.cursor()
            cursor.execute('INSERT INTO notes (content) VALUES (%s)', (note,))
            conn.commit()
            conn.close()
            return f'Added: {note}', 200
        except Exception as e:
            print(f'ERROR: DB connection failed: {e}')
            return f'Error: {e}', 500
    
    @app.route('/list')
    def list_notes():
        try:
            conn = get_connection()
            cursor = conn.cursor()
            cursor.execute('SELECT id, content, created_at FROM notes ORDER BY created_at DESC')
            rows = cursor.fetchall()
            conn.close()
            return '<br>'.join([f'{r[0]}: {r[1]} ({r[2]})' for r in rows]), 200
        except Exception as e:
            print(f'ERROR: DB connection failed: {e}')
            return f'Error: {e}', 500
    
    if __name__ == '__main__':
        app.run(host='0.0.0.0', port=80)
    APPEOF
    
    # Set environment variables for Tokyo RDS connection via TGW
    export DB_HOST="${var.tokyo_rds_endpoint}"
    export DB_USER="${var.db_username}"
    export DB_PASS="${var.db_password}"
    export DB_NAME="${var.db_name}"
    export DB_PORT="3306"
    
    # Run the application
    python3 /opt/app/app.py &
    EOF
}

# The EC2 instance
resource "aws_instance" "app" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private[0].id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_app.name

  user_data = local.user_data

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sp-ec201"
  })
}