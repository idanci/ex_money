defmodule ExMoney.RuleProcessor do
  use GenServer

  alias ExMoney.{Repo, Rule, Transaction, Category, Account, TransactionInfo}

  import Ecto.Query

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: :rule_processor)
  end

  def handle_cast({:process, transaction_id}, _state) do
    transaction = Transaction
    |> preload(:transaction_info)
    |> where([tr], tr.id == ^transaction_id)
    |> Repo.one

    transaction_info = transaction.transaction_info

    Rule
    |> where([r], r.account_id == ^transaction.account_id)
    |> Repo.all
    |> Enum.each(fn(rule) ->
      case rule.type do
        "assign_category" -> assign_category(rule, transaction, transaction_info)
        "withdraw_to_cash" -> withdraw_to_cash(rule, transaction, transaction_info)
      end
    end)

    {:noreply, %{}}
  end

  def handle_cast({:process_all, rule_id}, _state) do
    rule = Repo.get(Rule, rule_id)

    sql_like = "%#{rule.pattern}%"
    transactions = Repo.all(from tr in Transaction,
      join: tr_info in TransactionInfo, on: tr.id == tr_info.transaction_id,
      preload: [transaction_info: tr_info],
      where: tr.account_id == ^rule.account_id,
      where: ilike(tr.description, ^sql_like) or ilike(tr_info.payee, ^sql_like))

    Enum.each(transactions, fn(tr) ->
      GenServer.cast(:rule_processor, {:process, tr.id})
    end)

    {:noreply, %{}}
  end

  defp assign_category(rule, transaction, transaction_info) do
    {:ok, re} = Regex.compile(rule.pattern, "i")

    if Regex.match?(re, transaction_description(transaction, transaction_info)) do
      Transaction.update_changeset(transaction, %{category_id: rule.target_id})
      |> Repo.update
    end
  end

  defp withdraw_to_cash(rule, transaction, transaction_info) do
    {:ok, re} = Regex.compile(rule.pattern, "i")
    withdraw_category = Category.by_name("withdraw") |> Repo.one
    transfer_category = Category.by_name("transfer") |> Repo.one
    account = Repo.get(Account, rule.target_id)

    if Regex.match?(re, transaction_description(transaction, transaction_info)) &&
      transaction.category_id == transfer_category.id &&
      Decimal.compare(transaction.amount, Decimal.new(0)) == Decimal.new(-1) do

      Repo.transaction(fn ->
        Transaction.changeset_custom(%Transaction{},
          %{
            "amount" => transaction.amount,
            "category_id" => withdraw_category.id,
            "account_id" => account.id,
            "made_on" => transaction.made_on,
            "user_id" => transaction.user_id,
            "type" => "expense"
          }
        )
        |> Repo.insert

        # transaction.amount is negative, sub with something with negative => add
        new_balance = Decimal.sub(account.balance, transaction.amount)

        Account.update_custom_changeset(account, %{balance: new_balance})
        |> Repo.update!
      end)
    end
  end

  defp transaction_description(transaction, transaction_info) do
    transaction.description <> " " <> transaction_info.payee
  end
end
