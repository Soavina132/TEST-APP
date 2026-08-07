-- Add missing deposit notification trigger
-- The function _notify_deposit_created existed but was never attached
DROP TRIGGER IF EXISTS trg_notify_deposit_created ON public.deposits;
CREATE TRIGGER trg_notify_deposit_created
  AFTER INSERT ON public.deposits
  FOR EACH ROW EXECUTE FUNCTION public._notify_deposit_created();
