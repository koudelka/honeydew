defmodule EctoPollQueueExample.Notify do
  alias EctoPollQueueExample.User
  alias EctoPollQueueExample.Repo

  def run(id) do
    user = Repo.get(User, id)

    if user.sleep do
      Process.sleep(user.sleep)
    end

    if user.from do
      send(user.from, {:notify_job_ran, id})
    end

    if user.should_fail do
      raise "notifier's totally busted dude!"
    end
  end
end
