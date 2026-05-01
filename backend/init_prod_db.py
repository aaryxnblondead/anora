#!/usr/bin/env python3
"""
Production database initialization script.
Run this once before deploying the backend to production.

Usage:
  python init_prod_db.py

Environment Variables Required:
  - DATABASE_URL: PostgreSQL connection string (e.g., postgresql://user:pass@host:5432/dbname)
"""

import os
import sys
from pathlib import Path
from dotenv import load_dotenv
import psycopg2

# Add backend directory to path
sys.path.insert(0, str(Path(__file__).parent))

from fl_coordinator import ensure_fl_tables, create_fl_round

def main():
    # Load environment
    load_dotenv(dotenv_path=Path(__file__).with_name(".env"))
    load_dotenv()
    
    database_url = os.getenv("DATABASE_URL")
    if not database_url:
        print("❌ ERROR: DATABASE_URL not set. Please set it before running init.")
        sys.exit(1)
    
    print(f"📡 Connecting to database: {database_url[:50]}...")
    
    try:
        connection = psycopg2.connect(database_url, connect_timeout=10)
        print("✅ Connected to database.")
    except psycopg2.OperationalError as e:
        print(f"❌ ERROR: Failed to connect to database: {e}")
        sys.exit(1)
    
    # Step 1: Initialize FL tables
    print("\n📋 Creating FL tables...")
    try:
        ensure_fl_tables(connection)
        print("✅ FL tables created (or already exist).")
    except Exception as e:
        print(f"❌ ERROR: Failed to create FL tables: {e}")
        connection.close()
        sys.exit(1)
    
    # Step 2: Create FL round 0
    print("\n🔄 Creating FL round 0...")
    try:
        result = create_fl_round(
            connection=connection,
            round_id=0,
            model_version=0,
            min_clients=100
        )
        print(f"✅ FL round 0 created: {result}")
    except Exception as e:
        # It's OK if round 0 already exists (ON CONFLICT DO NOTHING)
        if "already" in str(e).lower() or "conflict" in str(e).lower():
            print(f"⚠️  FL round 0 already exists (OK)")
        else:
            print(f"❌ ERROR: Failed to create FL round 0: {e}")
            connection.close()
            sys.exit(1)
    
    connection.close()
    
    print("\n" + "="*60)
    print("✅ DATABASE INITIALIZATION COMPLETE")
    print("="*60)
    print("\nNext steps:")
    print("1. Deploy the backend to production (App Runner)")
    print("2. Run: curl https://xydctnf6j6.us-east-1.awsapprunner.com/health")
    print("3. If db_ready=true, you're ready for FL clients")
    print("\nFL Infrastructure Status:")
    print("  ✅ Tables created: fl_clients, fl_rounds, fl_gradients, fl_model_versions, fl_convergence_metrics")
    print("  ✅ Round 0 initialized (min_clients=100)")
    print("  ✅ Ready for device registration and gradient submission")

if __name__ == "__main__":
    main()
