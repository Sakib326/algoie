defmodule Algoie.Repo.Migrations.NormalizeTenantWorkspaceSlugs do
  use Ecto.Migration

  def up do
    execute("""
    WITH candidates AS (
      SELECT id,
             trim(both '-' from lower(regexp_replace(name, '[^a-zA-Z0-9]+', '-', 'g'))) AS clean_slug
      FROM public.tenants
    ), unique_candidates AS (
      SELECT clean_slug
      FROM candidates
      WHERE length(clean_slug) BETWEEN 3 AND 63
      GROUP BY clean_slug
      HAVING count(*) = 1
    )
    UPDATE public.tenants t
    SET slug = c.clean_slug
    FROM candidates c
    JOIN unique_candidates u ON u.clean_slug = c.clean_slug
    WHERE t.id = c.id
      AND NOT EXISTS (
        SELECT 1 FROM public.tenants other
        WHERE other.slug = c.clean_slug AND other.id != t.id
      )
    """)
  end

  def down, do: :ok
end
