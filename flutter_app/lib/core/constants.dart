class AppConstants {
  // ── Supabase ──────────────────────────────────────────────────────────────
  // Replace these with your actual Supabase project values
  static const supabaseUrl = 'https://umuqhnzqutumhuykuiwc.supabase.co';
  static const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVtdXFobnpxdXR1bWh1eWt1aXdjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ5NTI4ODEsImV4cCI6MjA5MDUyODg4MX0.YfgVuhc3u1cI8BK2xAgw_s5b-wImt1FStemLERDrr8U';

  // ── FastAPI AI Worker ─────────────────────────────────────────────────────
  // 10.0.2.2 = your PC's localhost from Android emulator
  // If using real phone: replace with your PC's local IP e.g. 192.168.1.x
  static const aiWorkerUrl = 'http://10.88.225.19:8000';

  // ── Google Maps ───────────────────────────────────────────────────────────
  static const googleMapsApiKey = 'AIzaSyAjke8r2nyK1lDAM88W27uy4juitUPvRSI';

  // ── Storage Buckets ───────────────────────────────────────────────────────
  static const bucketPotholeImages = 'pothole-images';
  static const bucketDepthMaps     = 'depth-maps';
  static const bucketRepairPhotos  = 'repair-photos';

  // ── Duplicate Detection ───────────────────────────────────────────────────
  // Radius in metres — reports within this distance are considered duplicates
  static const duplicateRadiusMetres = 15.0;

  // ── Photo Quality ─────────────────────────────────────────────────────────
  static const blurThreshold       = 50.0;   // 50 for emulator/dev, 80 for production
  static const brightnessThreshold = 30.0;   // Mean pixel brightness

  // ── Currency ──────────────────────────────────────────────────────────────
  static const currencySymbol = '₹';
  static const currencyCode   = 'INR';

  // ── Repair Cost Estimates (INR) ───────────────────────────────────────────
  static const shallowCostMin  = 500.0;
  static const shallowCostMax  = 1500.0;
  static const moderateCostMin = 1500.0;
  static const moderateCostMax = 5000.0;
  static const deepCostMin     = 5000.0;
  static const deepCostMax     = 15000.0;

  // ── Map ───────────────────────────────────────────────────────────────────
  static const defaultLat  = 20.5937;   // India centre
  static const defaultLng  = 78.9629;
  static const defaultZoom = 12.0;
}