aws_region   = "ap-south-1"
environment  = "dev"
project_name = "gitops-platform"
project_owner = "prajaktanaik"

# Database configuration
db_instance_class = "db.t3.micro"  # Use db.t3.small for production
db_allocated_storage = 20

# Security settings
enable_deletion_protection = false  # Set to true for production

# Logging
log_retention_days = 7  #