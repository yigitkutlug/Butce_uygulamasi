from fastapi import APIRouter, Depends
from fastapi.responses import Response

from app.core.deps import get_current_user
from app.services.export import build_csv_report

router = APIRouter()


@router.get("/export/csv")
async def export_csv(user=Depends(get_current_user)):
    csv_text = await build_csv_report(user["id"])
    return Response(
        content=csv_text,
        media_type="text/csv",
        headers={"Content-Disposition": 'attachment; filename="budget_report.csv"'},
    )

