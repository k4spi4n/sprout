from datetime import datetime

from sqlalchemy import DateTime, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from .database import Base


class Plant(Base):
    __tablename__ = "plants"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(80))
    species: Mapped[str | None] = mapped_column(String(120))
    location: Mapped[str | None] = mapped_column(String(80))
    water_every_days: Mapped[int]
    notes: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    # Roadmap: CareEvent model (water / fertilize / mist / repot) -> see ROADMAP.md
