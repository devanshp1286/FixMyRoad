import os
from supabase import create_client, Client

SUPABASE_URL        = os.environ.get("SUPABASE_URL", "https://umuqhnzqutumhuykuiwc.supabase.co")
SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVtdXFobnpxdXR1bWh1eWt1aXdjIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NDk1Mjg4MSwiZXhwIjoyMDkwNTI4ODgxfQ.cMEbefXQvDj0XRdKkl_tpniFYDDl1EY2z7siqKKxJAs")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

def upload_image(path: str, image_bytes: bytes, bucket: str = "depth-maps") -> None:
    supabase.storage.from_(bucket).upload(
        path,
        image_bytes,
        file_options={"content-type": "image/png", "upsert": "true"},
    )

def get_public_url(bucket: str, path: str) -> str:
    return supabase.storage.from_(bucket).get_public_url(path)
