from fastapi import APIRouter, Depends, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import Plant
from ..schemas import PlantCreate, PlantOut

router = APIRouter(prefix="/api/plants", tags=["plants"])


@router.get("", response_model=list[PlantOut])
def list_plants(db: Session = Depends(get_db)):
    return db.scalars(select(Plant).order_by(Plant.created_at.desc(), Plant.id.desc())).all()


@router.post("", response_model=PlantOut, status_code=status.HTTP_201_CREATED)
def create_plant(payload: PlantCreate, db: Session = Depends(get_db)):
    plant = Plant(**payload.model_dump())
    db.add(plant)
    db.commit()
    db.refresh(plant)
    return plant
