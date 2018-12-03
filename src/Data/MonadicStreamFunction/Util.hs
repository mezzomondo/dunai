{-# LANGUAGE Arrows     #-}
{-# LANGUAGE Rank2Types #-}
-- | Useful auxiliary functions and definitions.
module Data.MonadicStreamFunction.Util where

-- External
import Control.Arrow
import Control.Category
import Control.Monad
import Control.Monad.Base
import Data.Monoid

-- Internal
import Data.MonadicStreamFunction.Core
import Data.MonadicStreamFunction.Instances.ArrowChoice ()
import Data.VectorSpace
import Prelude hiding (id, (.))

import Control.Monad.Trans.MSF.State

-- * Streams and sinks

-- | A stream is an 'MSF' that produces outputs, while ignoring the input.
-- It can obtain the values from a monadic context.
type MStream m a = MSF m () a

-- | A sink is an 'MSF' that consumes inputs, while producing no output.
-- It can consume the values with side effects.
type MSink   m a = MSF m a ()

-- * Lifting



-- * Analogues of 'map' and 'fmap'


-- | Apply an 'MSF' to every input. Freezes temporarily if the input is
-- 'Nothing', and continues as soon as a 'Just' is received.
mapMaybeS :: Monad m => MSF m a b -> MSF m (Maybe a) (Maybe b)
mapMaybeS msf = proc maybeA -> case maybeA of
  Just a  -> arr Just <<< msf -< a
  Nothing -> returnA          -< Nothing

-- * Adding side effects

-- | Applies a function to produce an additional side effect and passes the
-- input unchanged.
withSideEffect :: Monad m => (a -> m b) -> MSF m a a
withSideEffect method = (id &&& arrM method) >>> arr fst

-- | Produces an additional side effect and passes the input unchanged.
withSideEffect_ :: Monad m => m b -> MSF m a a
withSideEffect_ method = withSideEffect $ const method

-- * Delays

-- See also: 'iPre'

-- | Delay a signal by one sample.
iPre :: Monad m
     => a         -- ^ First output
     -> MSF m a a
-- iPre firsta = MSF $ \a -> return (firsta, iPre a)
iPre firsta = feedback firsta $ arr swap
  where swap (a,b) = (b, a)
-- iPre firsta = next firsta identity

-- | Preprends a fixed output to an 'MSF', shifting the output.
next :: Monad m => b -> MSF m a b -> MSF m a b
next b sf = sf >>> iPre b

-- | Buffers and returns the elements in FIFO order,
--   returning 'Nothing' whenever the buffer is empty.
fifo :: Monad m => MSF m [a] (Maybe a)
fifo = feedback [] $ proc (as, accum) -> do
  let accum' = accum ++ as
  returnA -< case accum' of
    []       -> (Nothing, [])
    (a : as) -> (Just a , as)

-- * Folding

-- ** Folding for 'VectorSpace' instances

-- | Count the number of simulation steps. Produces 1, 2, 3,...
count :: (Num n, Monad m) => MSF m a n
count = arr (const 1) >>> accumulateWith (+) 0

-- | Sums the inputs, starting from zero.
sumS :: (RModule v, Monad m) => MSF m v v
sumS = sumFrom zeroVector

-- | Sums the inputs, starting from an initial vector.
sumFrom :: (RModule v, Monad m) => v -> MSF m v v
sumFrom = accumulateWith (^+^)

-- ** Folding for monoids

-- | Accumulate the inputs, starting from 'mempty'.
mappendS :: (Monoid n, Monad m) => MSF m n n
mappendS = mappendFrom mempty
{-# INLINE mappendS #-}

-- | Accumulate the inputs, starting from an initial monoid value.
mappendFrom :: (Monoid n, Monad m) => n -> MSF m n n
mappendFrom = accumulateWith mappend

-- ** Generic folding \/ accumulation

-- | Applies a function to the input and an accumulator,
-- outputting the updated accumulator.
-- Equal to @\f s0 -> feedback s0 $ arr (uncurry f >>> dup)@.
accumulateWith :: Monad m => (a -> s -> s) -> s -> MSF m a s
accumulateWith f s0 = feedback s0 $ arr g
  where
    g (a, s) = let s' = f a s in (s', s')

-- | Applies a transfer function to the input and an accumulator,
-- returning the updated accumulator and output.
mealy :: Monad m => (a -> s -> (b, s)) -> s -> MSF m a b
mealy f s0 = feedback s0 $ arr $ uncurry f

-- * Unfolding

-- | Generate outputs using a step-wise generation function and an initial
-- value.
unfold :: Monad m => (a -> (b, a)) -> a -> MSF m () b
unfold f a = feedback a (arr (snd >>> f))

-- | Generate outputs using a step-wise generation function and an initial
-- value. Version of 'unfold' in which the output and the new accumulator
-- are the same. Should be equal to @\f a -> unfold (f >>> dup) a@.
repeatedly :: Monad m => (a -> a) -> a -> MSF m () a
repeatedly f = unfold $ f >>> dup
  where
    dup a = (a, a)


-- * Debugging

-- | Outputs every input sample, with a given message prefix.
trace :: Show a => String -> MSF IO a a
trace = traceWith putStrLn

-- | Outputs every input sample, with a given message prefix, using an
-- auxiliary printing function.
traceWith :: (Monad m, Show a) => (String -> m ()) -> String -> MSF m a a
traceWith method msg =
  withSideEffect (method . (msg ++) . show)

-- | Outputs every input sample, with a given message prefix, using an
-- auxiliary printing function, when a condition is met.
traceWhen :: (Monad m, Show a) => (a -> Bool) -> (String -> m ()) -> String -> MSF m a a
traceWhen cond method msg = withSideEffect $ \a ->
  when (cond a) $ method $ msg ++ show a

-- | Outputs every input sample, with a given message prefix, when a condition
-- is met, and waits for some input \/ enter to continue.
pauseOn :: Show a => (a -> Bool) -> String -> MSF IO a a
pauseOn cond = traceWhen cond $ \s -> print s >> getLine >> return ()
