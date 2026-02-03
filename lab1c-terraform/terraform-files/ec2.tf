# ec2.tf
# EC2 Application Server

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
    pip3 install flask pymysql boto3
    
    # Create application directory
    mkdir -p /opt/app
    cd /opt/app
    
    # Create the Flask application
    cat > app.py << 'APPEOF'
    import os
    import json
    import boto3
    import pymysql
    from flask import Flask, request
    
    app = Flask(__name__)
    region = "${var.aws_region}"
    secret_name = "${local.name_prefix}/rds/mysql"
    
    def get_db_creds():
        client = boto3.client('secretsmanager', region_name=region)
        response = client.get_secret_value(SecretId=secret_name)
        return json.loads(response['SecretString'])
    
    def get_connection():
        creds = get_db_creds()
        return pymysql.connect(
            host=creds['host'],
            user=creds['username'],
            password=creds['password'],
            database=creds['dbname'],
            port=int(creds['port'])
        )
    
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
            return 'Database initialized!', 200
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
    
    # Run the application
    python3 /opt/app/app.py &
    EOF
}

# The EC2 instance
resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_app.name

  user_data = local.user_data

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ec201"
  })

  depends_on = [
    aws_db_instance.main,
    aws_secretsmanager_secret_version.db_credentials
  ]
}