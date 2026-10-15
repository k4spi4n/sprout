from fastapi import APIRouter, status
from sqlalchemy import select

from ..database import DbSession
from ..models import Plant
from ..schemas import PlantCreate, PlantOut

router = APIRouter(prefix="/api/plants", tags=["plants"])


@router.get("", response_model=list[PlantOut])
def list_plants(db: DbSession):
    return db.scalars(select(Plant).order_by(Plant.created_at.desc(), Plant.id.desc())).all()


@router.post("", response_model=PlantOut, status_code=status.HTTP_201_CREATED)
def create_plant(payload: PlantCreate, db: DbSession):
    plant = Plant(**payload.model_dump())
    db.add(plant)
    db.commit()
    db.refresh(plant)
    return plant
