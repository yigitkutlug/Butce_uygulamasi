# AI-Powered Budget Tracking Application

This is a full-stack MVP for tracking income/expenses, AI-based categorization, analytics, predictions, and recommendations.

## Folder Structure

- backend/
  - app/
    - core/
    - db/
    - models/
    - routes/
    - services/
    - ml/
      - data/
- frontend/
  - lib/
    - screens/
    - services/
    - models/

## Backend Setup (FastAPI)

1. Create a virtual environment and install deps.

```bash
cd backend
python -m venv .venv
# Windows
.venv\Scripts\activate
pip install -r requirements.txt
```

2. Create a `.env` file from `.env.example` and fill your Atlas values.
   - `CORS_ALLOW_ORIGINS` must be a JSON array string (example is provided in `.env.example`).
   - `JWT_SECRET` must be changed to a strong random value.

3. In MongoDB Atlas:
- Create a DB user (Database Access)
- Add your IP to Network Access (for quick test you can temporarily use `0.0.0.0/0`)
- Replace `MONGO_URI` placeholders in `.env`

4. Start the API server.

```bash
uvicorn app.main:app --reload
```

API will be available at `http://127.0.0.1:8000`.

## Backend Tests

```bash
cd backend
pip install -r requirements-dev.txt
pytest
```

## ML Training

The model auto-trains on first use from `backend/app/ml/data/seed.csv`.
To manually retrain:

```bash
cd backend
python -m app.ml.train --text "taco" --label "Food"
```

You can also trigger retraining using:

```http
POST /retrain
```

## Flutter Setup

1. Install Flutter SDK.
2. Get dependencies.

```bash
cd frontend
flutter pub get
```

3. Run the app.

```bash
flutter run
```

`API_BASE_URL` can be overridden with `--dart-define`:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

Default behavior:
- Android emulator: `http://10.0.2.2:8000`
- Web/Desktop: `http://127.0.0.1:8000`

## Notes

- Income is stored as positive amounts.
- Expenses are stored as negative amounts.
- Category prediction uses TF-IDF + Logistic Regression.
- Recommendations are based on month-over-month changes.
- Retraining uses the current user's feedback data.
