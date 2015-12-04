defmodule ExMoney.Repo.Migrations.CreateAccount do
  use Ecto.Migration

  def change do
    create table(:accounts) do
      add :name, :string
      add :saltedge_account_id, :integer
      add :nature, :string
      add :balance, :decimal
      add :currency_code, :string
      add :saltedge_login_id, references(:logins, column: :saltedge_login_id)

      timestamps
    end

  end
end
