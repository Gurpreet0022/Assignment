import urllib.parse
from pymongo import MongoClient

# 1. Connection

username = "Gurpreet"
password = "gurpreet@16"
escaped_password = urllib.parse.quote_plus(password)
uri = f"mongodb+srv://{username}:{escaped_password}@cluster0.gngaygj.mongodb.net/?appName=Cluster0"

client = MongoClient(uri)

# --- THE FIX: Define specific pointers ---
source_db = client['nimbus_events']  
dest_db = client['test']            

def deep_clean_all():
    print("Start...")
    
    # Verify raw data exists first
    raw_count = source_db.user_activity_logs.count_documents({})
    print(f"Found raw documents in nimbus_events.")

    if raw_count == 0:
        print("Can't find the raw data in nimbus_events!")
        return

    # Pipeline
    activity_p = [
        {
            "$project": {
                "customer_id": {"$toInt": {"$ifNull": ["$customer_id", "$customerId"]}},
                "timestamp": {"$toDate": "$timestamp"},
                "session_duration_sec": {"$toDouble": {"$ifNull": ["$session_duration_sec", 0]}},
                "event_type": {"$ifNull": ["$event_type", "unknown"]}
            }
        },
        # Take results from 'nimbus_events' and push to 'test'
        {"$out": {"db": "test", "coll": "final_activity_logs"}}
    ]

    print("Executing move from nimbus_events to test...")
    source_db.user_activity_logs.aggregate(activity_p)
    
    # Verification after run
    print("Waiting for Atlas to update...")
    import time
    time.sleep(5) 
    
    final_count = dest_db.final_activity_logs.count_documents({})
    print(f"Success!documents are now in the 'test' database.")

if __name__ == "__main__":
    deep_clean_all()