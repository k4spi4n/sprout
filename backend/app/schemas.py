from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class PlantCreate(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    species: str | None = Field(default=None, max_length=120)
    location: str | None = Field(default=None, max_length=80)
    water_every_days: int = Field(ge=1, le=60)
    notes: str | None = None


class PlantOut(PlantCreate):
    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime
