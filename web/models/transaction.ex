defmodule ExMoney.Transaction do
  use ExMoney.Web, :model

  alias ExMoney.Transaction

  import Ecto.Query

  schema "transactions" do
    field :saltedge_transaction_id, :integer
    field :mode, :string
    field :status, :string
    field :made_on, Ecto.Date
    field :amount, :decimal
    field :currency_code, :string
    field :description, :string
    field :duplicated, :boolean, default: false

    has_one :transaction_info, ExMoney.TransactionInfo, on_delete: :delete_all
    belongs_to :category, ExMoney.Category
    belongs_to :user, ExMoney.User
    belongs_to :account, ExMoney.Account
    belongs_to :saltedge_account, ExMoney.Account,
      foreign_key: :saltedge_account_id,
      references: :saltedge_account_id

    timestamps
  end

  @required_fields ~w(
    saltedge_transaction_id
    mode
    status
    made_on
    amount
    currency_code
    description
    duplicated
    saltedge_account_id
    account_id
    user_id
  )
  @optional_fields ~w(category_id)

  def changeset(model, params \\ :empty) do
    model
    |> cast(params, @required_fields, @optional_fields)
  end

  def changeset_custom(model, params \\ :empty) do
    model
    |> cast(params, ~w(amount category_id account_id made_on user_id), ~w(description ))
    |> negate_amount(params)
  end

  def update_changeset(model, params \\ :empty) do
    model
    |> cast(params, ~w(), ~w(category_id description))
  end

  def negate_amount(changeset, :empty), do: changeset
  def negate_amount(changeset, %{"type" => "income"}), do: changeset

  def negate_amount(changeset, %{"type" => "expense"}) do
    case Ecto.Changeset.fetch_change(changeset, :amount) do
      {:ok, amount} ->
        Ecto.Changeset.put_change(changeset, :amount, Decimal.mult(amount, Decimal.new(-1)))
      :error -> changeset
    end
  end

  def by_user_id(user_id) do
    from tr in Transaction,
      where: tr.user_id == ^user_id
  end

  def by_saltedge_transaction_id(transaction_id) do
    from tr in Transaction,
      where: tr.saltedge_transaction_id == ^transaction_id,
      limit: 1
  end

  def recent do
    current_date = Timex.Date.local
    from = Timex.Date.shift(current_date, days: -15)

    from tr in Transaction,
      where: tr.made_on >= ^from,
      preload: [:transaction_info, :category, :account],
      order_by: [desc: tr.inserted_at]
  end

  def new_since(time, account_id) do
    from tr in Transaction,
      where: tr.inserted_at >= ^time,
      where: tr.account_id == ^account_id
  end

  def by_month(account_id, from, to) do
    from tr in Transaction,
      where: tr.made_on >= ^from,
      where: tr.made_on <= ^to,
      where: tr.account_id == ^account_id
  end

  def by_month_by_category(account_id, from, to, category_ids) do
    Transaction.by_month(account_id, from, to)
    |> where([tr], tr.category_id in ^(category_ids))
    |> preload([:transaction_info, :category, :account])
  end

  def expenses_by_month(account_id, from, to) do
    Transaction.by_month(account_id, from ,to)
    |> where([tr], tr.amount < 0)
    |> preload([:transaction_info, :category, :account])
  end

  def income_by_month(account_id, from ,to) do
    Transaction.by_month(account_id, from ,to)
    |> where([tr], tr.amount > 0)
    |> preload([:transaction_info, :category, :account])
  end

  def group_by_month_by_category(account_id, from, to) do
    from tr in Transaction,
      join: c in assoc(tr, :category),
      where: tr.made_on >= ^from,
      where: tr.made_on <= ^to,
      where: tr.account_id == ^account_id,
      group_by: [c.id],
      select: {c, sum(tr.amount)},
      having: sum(tr.amount) < 0
  end

  # FIXME cache instead of db
  def newest(saltedge_account_id) do
    from tr in Transaction,
      where: tr.saltedge_account_id == ^saltedge_account_id,
      order_by: [desc: tr.made_on],
      limit: 1
  end

  def newest do
    from tr in Transaction,
      order_by: [desc: tr.made_on],
      limit: 1
  end
end
