"""Create plants, or adopt the matching schema from the original create_all app."""
from alembic import op
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
import sqlalchemy as sa

revision = "0001_plants"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    metadata = sa.MetaData()
    plants = sa.Table(
        "plants", metadata,
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(80), nullable=False),
        sa.Column("species", sa.String(120)),
        sa.Column("location", sa.String(80)),
        sa.Column("water_every_days", sa.Integer(), nullable=False),
        sa.Column("notes", sa.Text()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.now()),
    )
    connection = op.get_bind()
    if op.get_context().as_sql:
        plants.create(connection, checkfirst=False)
        return
    inspector = sa.inspect(connection)
    if inspector.has_table("plants"):
        # Never stamp an unknown legacy schema as successfully migrated.
        migration_context = MigrationContext.configure(connection, opts={
            "include_object": lambda obj, name, kind, reflected, compare_to:
                kind != "table" or name == "plants",
            "compare_type": True,
            "compare_server_default": True,
        })
        primary_key = inspector.get_pk_constraint("plants")["constrained_columns"]
        if primary_key != ["id"] or compare_metadata(migration_context, metadata):
            raise RuntimeError("Legacy plants schema differs from revision 0001; reconcile it before upgrading")
    else:
        plants.create(connection)


def downgrade():
    op.drop_table("plants")
