{-# LANGUAGE CPP #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE TypeFamilies #-}

#ifdef KIND_POLYMORPHIC_TYPEABLE
{-# LANGUAGE DeriveDataTypeable #-}
#endif

#if MIN_VERSION_transformers(0,4,0)
-- ExceptT was introduced in transformers == 0.4.0.0 and it deprecated ErrorT.
-- That is also the reason why ErrorT instance is not provided.
#define HAVE_EXCEPTT
#endif

#if MIN_VERSION_base(4,7,0)
-- Module Data.Proxy, that defines Proxy data type, was introduced in
-- base == 4.7.0.0.
#define HAVE_PROXY
#endif

-- |
-- Module:       $HEADER$
-- Description:  Generic folding for various endomorphism representations.
-- Copyright:    (c) 2014-2015, Peter Trško
-- License:      BSD3
--
-- Maintainer:   peter.trsko@gmail.com
-- Stability:    experimental
-- Portability:  CPP, DeriveDataTypeable, DeriveGeneric, FlexibleInstances,
--               NoImplicitPrelude, TypeFamilies
--
-- Generic folding for various endomorphism representations.
module Data.Monoid.Endo.Fold
    (
    -- * Usage Examples
    -- $usageExample

    -- ** Using with optparse-applicative
    -- $optparseApplicativeExample

    -- * Generic Endomorphism Folding
      foldEndo
    , dualFoldEndo

    -- ** Type Classes
    , FoldEndoArgs(..)
    , AnEndo(..)

    -- ** Type Wrappers
    , WrappedFoldable(..)

    -- * Utility Functions
    , (&$)
    , (<&$>)
    , embedEndoWith
    , embedDualEndoWith
    )
  where

import Control.Applicative (Applicative(pure), Const(Const))
import Control.Monad (Monad(return))
import Data.Either (Either(Right))
import Data.Foldable (Foldable(foldMap))
import Data.Function ((.), id)
import Data.Functor (Functor(fmap))
import Data.Functor.Identity (Identity(Identity))
import Data.Maybe (Maybe(Just, Nothing))
import Data.Monoid (Dual(Dual, getDual), Endo(Endo), Monoid(mempty, mconcat), (<>))
import GHC.Generics (Generic)
import System.IO (IO)
import Text.Read (Read)
import Text.Show (Show)

#ifdef KIND_POLYMORPHIC_TYPEABLE
import Data.Data (Data)
import Data.Typeable (Typeable)
#endif

#ifdef HAVE_PROXY
import Data.Proxy (Proxy(Proxy))
#endif

#ifdef HAVE_EXCEPTT
import Control.Monad.Trans.Except (ExceptT)
#endif
import Control.Monad.Trans.Identity (IdentityT)
import Control.Monad.Trans.List (ListT)
import Control.Monad.Trans.Maybe (MaybeT)
import Control.Monad.Trans.Reader (ReaderT)
import Control.Monad.Trans.RWS (RWST)
import qualified Control.Monad.Trans.RWS.Strict as Strict (RWST)
import Control.Monad.Trans.State (StateT)
import qualified Control.Monad.Trans.State.Strict as Strict (StateT)
import Control.Monad.Trans.Writer (WriterT)
import qualified Control.Monad.Trans.Writer.Strict as Strict (WriterT)
import Data.Functor.Compose (Compose)
import Data.Functor.Product (Product)
import Data.Functor.Reverse (Reverse)


-- | Fold all variously represented endomorphisms in to one endomorphism.
--
-- Order in which endomorphisms are folded is preserved:
--
-- >>> foldEndo (Endo (1:)) [(2:), (3:)] `appEndo` []
-- [1,2,3]
--
-- For numbers it would look like:
--
-- >>> foldEndo (Endo (+1)) [(+2), (*3)] `appEndo` 1
-- 6
--
-- Above can be seen as:
--
-- >>> (+1) . (+2) . (*3) $ 1
-- 6
foldEndo :: FoldEndoArgs args => args
foldEndo = foldEndoArgs mempty

-- | Same as 'foldEndo', but folds endomorphisms in reverse order.
--
-- Following are the same examples as for 'foldEndo' function. Please, note the
-- differences in results.
--
-- Order in which endomorphisms are folded is reversed:
--
-- >>> dualFoldEndo (Endo (1:)) [(2:), (3:)] `appEndo` []
-- [2,3,1]
--
-- For numbers it would look like:
--
-- >>> dualFoldEndo (Endo (+1)) [(+2), (*3)] `appEndo` 1
-- 12
--
-- Above can be seen as:
--
-- >>> (*3) . (+2) . (+1) $ 1
-- 12
dualFoldEndo :: FoldEndoArgs args => args
dualFoldEndo = dualFoldEndoArgs mempty

-- {{{ FoldEndoArgs Type Class ------------------------------------------------

-- | Class of arguments for 'foldEndo' and its dual 'dualFoldEndo' functions.
--
-- Note that results are instances of this ('FoldEndoArgs') class and
-- endomorphism representations are instances of 'AnEndo' type class.
class FoldEndoArgs a where
    -- | Extracts type of a value that is modified by the result.
    type ResultOperatesOn a

    -- | Result type of the whole endomorphism folding. It can be used to
    -- restrict the result of 'foldEndo' and 'dualFoldEndoArgs'. Example:
    --
    -- @
    -- -- Type restricted version of 'foldEndo' that forces the result of the
    -- -- whole folding machinery to be \"'Endo' Int\".
    -- myFoldEndo
    --     :: ('Result' args ~ 'Endo' Int, 'FoldEndoArgs' args)
    --     => args -> args
    -- myFoldEndo = 'foldEndo'
    -- @
    type Result a

    foldEndoArgs     ::       Endo (ResultOperatesOn a)  -> a
    dualFoldEndoArgs :: Dual (Endo (ResultOperatesOn a)) -> a
#ifdef HAVE_MINIMAL_PRAGMA
    {-# MINIMAL foldEndoArgs, dualFoldEndoArgs #-}
#endif

instance
    ( AnEndo a
    , FoldEndoArgs r
    , EndoOperatesOn a ~ ResultOperatesOn r
    ) => FoldEndoArgs (a -> r)
  where
    type ResultOperatesOn (a -> r) = ResultOperatesOn r
    type Result (a -> r) = Result r
    foldEndoArgs     e e' = foldEndoArgs     (e <> anEndo    e')
    dualFoldEndoArgs e e' = dualFoldEndoArgs (e <> aDualEndo e')

instance FoldEndoArgs (Endo a) where
    type ResultOperatesOn (Endo a) = a
    type Result (Endo a) = Endo a
    foldEndoArgs              = id
    dualFoldEndoArgs (Dual e) = e

instance (Monoid c, FoldEndoArgs r) => FoldEndoArgs (Const c r) where
    type ResultOperatesOn (Const c r) = ResultOperatesOn r
    type Result (Const c r) = Const c (Result r)
    foldEndoArgs     _ = Const mempty
    dualFoldEndoArgs _ = Const mempty

instance FoldEndoArgs r => FoldEndoArgs (Either e r) where
    type ResultOperatesOn (Either e r) = ResultOperatesOn r
    type Result (Either e r) = Either e (Result r)
    foldEndoArgs     = Right . foldEndoArgs
    dualFoldEndoArgs = Right . dualFoldEndoArgs

instance FoldEndoArgs r => FoldEndoArgs (Identity r) where
    type ResultOperatesOn (Identity r) = ResultOperatesOn r
    type Result (Identity r) = Identity (Result r)
    foldEndoArgs     = Identity . foldEndoArgs
    dualFoldEndoArgs = Identity . dualFoldEndoArgs

instance FoldEndoArgs r => FoldEndoArgs (IO r) where
    type ResultOperatesOn (IO r) = ResultOperatesOn r
    type Result (IO r) = IO (Result r)
    foldEndoArgs     = pure . foldEndoArgs
    dualFoldEndoArgs = pure . dualFoldEndoArgs

instance FoldEndoArgs r => FoldEndoArgs (Maybe r) where
    type ResultOperatesOn (Maybe r) = ResultOperatesOn r
    type Result (Maybe r) = Maybe (Result r)
    foldEndoArgs     = Just . foldEndoArgs
    dualFoldEndoArgs = Just . dualFoldEndoArgs

-- {{{ Transformers -----------------------------------------------------------

-- {{{ Functor Transformers ---------------------------------------------------

instance
    (Applicative f, Applicative g, FoldEndoArgs r)
    => FoldEndoArgs (Compose f g r)
  where
    type ResultOperatesOn (Compose f g r) = ResultOperatesOn r
    type Result (Compose f g r) = Compose f g (Result r)
    foldEndoArgs     = pure . foldEndoArgs
    dualFoldEndoArgs = pure . dualFoldEndoArgs

instance
    (Applicative f, Applicative g, FoldEndoArgs r)
    => FoldEndoArgs (Product f g r)
  where
    type ResultOperatesOn (Product f g r) = ResultOperatesOn r
    type Result (Product f g r) = Product f g (Result r)
    foldEndoArgs     = pure . foldEndoArgs
    dualFoldEndoArgs = pure . dualFoldEndoArgs

-- }}} Functor Transformers ---------------------------------------------------

-- {{{ Monad Transformers -----------------------------------------------------

-- | This instance can be used in cases when there is no 'FoldEndoArgs'
-- instance for a specific 'Applicative' functor. Example:
--
-- @
-- 'Control.Monad.Trans.Identity.runIdentityT' $ 'foldEndo'
--     \<*\> 'IdentityT' parseSomething
--     \<*\> 'IdentityT' parseSomethingElse
-- @
instance (Applicative f, FoldEndoArgs r) => FoldEndoArgs (IdentityT f r) where
    type ResultOperatesOn (IdentityT f r) = ResultOperatesOn r
    type Result (IdentityT f r) = IdentityT f (Result r)
    foldEndoArgs     = pure . foldEndoArgs
    dualFoldEndoArgs = pure . dualFoldEndoArgs

#ifdef HAVE_EXCEPTT
instance
    ( Monad m
#ifndef APPLICATIVE_MONAD
    , Functor m
#endif
    , FoldEndoArgs r
    ) => FoldEndoArgs (ExceptT e m r)
  where
    type ResultOperatesOn (ExceptT e m r) = ResultOperatesOn r
    type Result (ExceptT e m r) = ExceptT e m (Result r)
    foldEndoArgs     = pure . foldEndoArgs
    dualFoldEndoArgs = pure . dualFoldEndoArgs
#endif

instance (Applicative f, FoldEndoArgs r) => FoldEndoArgs (ListT f r) where
    type ResultOperatesOn (ListT f r) = ResultOperatesOn r
    type Result (ListT f r) = ListT f (Result r)
    foldEndoArgs     = pure . foldEndoArgs
    dualFoldEndoArgs = pure . dualFoldEndoArgs

instance
    ( Monad m
#ifndef APPLICATIVE_MONAD
    , Functor m
#endif
    , FoldEndoArgs r
    ) => FoldEndoArgs (MaybeT m r) where
    type ResultOperatesOn (MaybeT m r) = ResultOperatesOn r
    type Result (MaybeT m r) = MaybeT m (Result r)
    foldEndoArgs     = return . foldEndoArgs
    dualFoldEndoArgs = return . dualFoldEndoArgs

instance (Applicative f, FoldEndoArgs r) => FoldEndoArgs (ReaderT r' f r) where
    type ResultOperatesOn (ReaderT r' f r) = ResultOperatesOn r
    type Result (ReaderT r' f r) = ReaderT r' f (Result r)
    foldEndoArgs     = pure . foldEndoArgs
    dualFoldEndoArgs = pure . dualFoldEndoArgs

instance
    ( Monad m
#ifndef APPLICATIVE_MONAD
    , Functor m
#endif
    , Monoid w
    , FoldEndoArgs r
    ) => FoldEndoArgs (RWST r' w s m r)
  where
    type ResultOperatesOn (RWST r' w s m r) = ResultOperatesOn r
    type Result (RWST r' w s m r) = RWST r' w s m (Result r)
    foldEndoArgs     = return . foldEndoArgs
    dualFoldEndoArgs = return . dualFoldEndoArgs

instance
    ( Monad m
#ifndef APPLICATIVE_MONAD
    , Functor m
#endif
    , Monoid w
    , FoldEndoArgs r
    ) => FoldEndoArgs (Strict.RWST r' w s m r)
  where
    type ResultOperatesOn (Strict.RWST r' w s m r) = ResultOperatesOn r
    type Result (Strict.RWST r' w s m r) = Strict.RWST r' w s m (Result r)
    foldEndoArgs     = return . foldEndoArgs
    dualFoldEndoArgs = return . dualFoldEndoArgs

instance (Monad m, FoldEndoArgs r) => FoldEndoArgs (StateT s m r) where
    type ResultOperatesOn (StateT s m r) = ResultOperatesOn r
    type Result (StateT s m r) = StateT s m (Result r)
    foldEndoArgs     = return . foldEndoArgs
    dualFoldEndoArgs = return . dualFoldEndoArgs

instance (Monad m, FoldEndoArgs r) => FoldEndoArgs (Strict.StateT s m r) where
    type ResultOperatesOn (Strict.StateT s m r) = ResultOperatesOn r
    type Result (Strict.StateT s m r) = Strict.StateT s m (Result r)
    foldEndoArgs     = return . foldEndoArgs
    dualFoldEndoArgs = return . dualFoldEndoArgs

instance
    (Applicative f, FoldEndoArgs r, Monoid w) => FoldEndoArgs (WriterT w f r)
  where
    type ResultOperatesOn (WriterT w f r) = ResultOperatesOn r
    type Result (WriterT w f r) = WriterT w f (Result r)
    foldEndoArgs     = pure . foldEndoArgs
    dualFoldEndoArgs = pure . dualFoldEndoArgs

instance
    (Applicative f, FoldEndoArgs r, Monoid w)
    => FoldEndoArgs (Strict.WriterT w f r)
  where
    type ResultOperatesOn (Strict.WriterT w f r) = ResultOperatesOn r
    type Result (Strict.WriterT w f r) = Strict.WriterT w f (Result r)
    foldEndoArgs     = pure . foldEndoArgs
    dualFoldEndoArgs = pure . dualFoldEndoArgs

-- }}} Monad Transformers -----------------------------------------------------

-- }}} Transformers -----------------------------------------------------------

-- {{{ FoldEndoArgs Type Class ------------------------------------------------

-- {{{ AnEndo Type Class ------------------------------------------------------

-- | Class that represents various endomorphism representation. In other words
-- anything that encodes @a -> a@ can be instance of this class.
class AnEndo a where
    -- | Extract type on which endomorphism operates, e.g. for
    -- @'Endo' a@ it would be @a@.
    type EndoOperatesOn a

    -- | Convert value encoding @a -> a@ in to 'Endo'. Default implementation:
    --
    -- @
    -- 'anEndo' = 'getDual' . 'aDualEndo'
    -- @
    anEndo :: a -> Endo (EndoOperatesOn a)
    anEndo = getDual . aDualEndo

    -- | Dual to 'anEndo'. Default implementation:
    --
    -- @
    -- 'aDualEndo' = 'Dual' . 'anEndo'
    -- @
    aDualEndo :: a -> Dual (Endo (EndoOperatesOn a))
    aDualEndo = Dual . anEndo

#if HAVE_MINIMAL_PRAGMA
    {-# MINIMAL anEndo | aDualEndo #-}
#endif

instance AnEndo (Endo a) where
    type EndoOperatesOn (Endo a) = a
    anEndo = id

instance AnEndo (a -> a) where
    type EndoOperatesOn (a -> a) = a
    anEndo = Endo

instance AnEndo a => AnEndo (Maybe a) where
    type EndoOperatesOn (Maybe a) = EndoOperatesOn a

    anEndo Nothing  = mempty
    anEndo (Just e) = anEndo e

#ifdef HAVE_PROXY
-- | Constructs identity endomorphism for specified phantom type.
instance AnEndo (Proxy a) where
    type EndoOperatesOn (Proxy a) = a

    anEndo    Proxy = mempty
    aDualEndo Proxy = mempty
#endif

-- {{{ Foldable Instances -----------------------------------------------------

-- | Wrapper for 'Foldable' instances.
--
-- This allows using 'foldEndo' and 'dualFoldEndo' for any 'Foldable' instance
-- without the need for @OverlappingInstances@ language extension.
newtype WrappedFoldable f a = WrapFoldable {getFoldable :: f a}
  deriving
    ( Generic
    , Read
    , Show
#ifdef KIND_POLYMORPHIC_TYPEABLE
    , Data
    , Typeable
#endif
    )

instance (Foldable f, AnEndo a) => AnEndo (WrappedFoldable f a) where
    type EndoOperatesOn (WrappedFoldable f a) = EndoOperatesOn a
    anEndo    (WrapFoldable fa) = foldMap anEndo    fa
    aDualEndo (WrapFoldable fa) = foldMap aDualEndo fa

instance AnEndo a => AnEndo [a] where
    type EndoOperatesOn [a] = EndoOperatesOn a
    anEndo    = anEndo    . WrapFoldable
    aDualEndo = aDualEndo . WrapFoldable

-- {{{ Transformers -----------------------------------------------------------

-- | Fold in reverese order.
instance (Foldable f, AnEndo a) => AnEndo (Reverse f a) where
    type EndoOperatesOn (Reverse f a) = EndoOperatesOn a
    anEndo    = anEndo    . WrapFoldable
    aDualEndo = aDualEndo . WrapFoldable

-- }}} Transformers -----------------------------------------------------------

-- }}} Foldable Instances -----------------------------------------------------

-- {{{ Instances For Tuples ---------------------------------------------------

instance
    ( AnEndo a
    , AnEndo b
    , EndoOperatesOn a ~ EndoOperatesOn b
    ) => AnEndo (a, b)
  where
    type EndoOperatesOn (a, b) = EndoOperatesOn a
    anEndo    (a, b) = anEndo    a <> anEndo    b
    aDualEndo (a, b) = aDualEndo a <> aDualEndo b

instance
    ( AnEndo a
    , AnEndo b
    , AnEndo c
    , EndoOperatesOn a ~ EndoOperatesOn b
    , EndoOperatesOn a ~ EndoOperatesOn c
    ) => AnEndo (a, b, c)
  where
    type EndoOperatesOn (a, b, c) = EndoOperatesOn a
    anEndo    (a, b, c) = anEndo    a <> anEndo    b <> anEndo    c
    aDualEndo (a, b, c) = aDualEndo a <> aDualEndo b <> aDualEndo c

instance
    ( AnEndo a1
    , AnEndo a2
    , AnEndo a3
    , AnEndo a4
    , EndoOperatesOn a1 ~ EndoOperatesOn a2
    , EndoOperatesOn a1 ~ EndoOperatesOn a3
    , EndoOperatesOn a1 ~ EndoOperatesOn a4
    ) => AnEndo (a1, a2, a3, a4)
  where
    type EndoOperatesOn (a1, a2, a3, a4) = EndoOperatesOn a1
    anEndo (a1, a2, a3, a4) = mconcat
        [ anEndo a1
        , anEndo a2
        , anEndo a3
        , anEndo a4
        ]

    aDualEndo (a1, a2, a3, a4) = mconcat
        [ aDualEndo a1
        , aDualEndo a2
        , aDualEndo a3
        , aDualEndo a4
        ]

instance
    ( AnEndo a1
    , AnEndo a2
    , AnEndo a3
    , AnEndo a4
    , AnEndo a5
    , EndoOperatesOn a1 ~ EndoOperatesOn a2
    , EndoOperatesOn a1 ~ EndoOperatesOn a3
    , EndoOperatesOn a1 ~ EndoOperatesOn a4
    , EndoOperatesOn a1 ~ EndoOperatesOn a5
    ) => AnEndo (a1, a2, a3, a4, a5)
  where
    type EndoOperatesOn (a1, a2, a3, a4, a5) = EndoOperatesOn a1

    anEndo (a1, a2, a3, a4, a5) = mconcat
        [ anEndo a1
        , anEndo a2
        , anEndo a3
        , anEndo a4
        , anEndo a5
        ]

    aDualEndo (a1, a2, a3, a4, a5) = mconcat
        [ aDualEndo a1
        , aDualEndo a2
        , aDualEndo a3
        , aDualEndo a4
        , aDualEndo a5
        ]

instance
    ( AnEndo a1
    , AnEndo a2
    , AnEndo a3
    , AnEndo a4
    , AnEndo a5
    , AnEndo a6
    , EndoOperatesOn a1 ~ EndoOperatesOn a2
    , EndoOperatesOn a1 ~ EndoOperatesOn a3
    , EndoOperatesOn a1 ~ EndoOperatesOn a4
    , EndoOperatesOn a1 ~ EndoOperatesOn a5
    , EndoOperatesOn a1 ~ EndoOperatesOn a6
    ) => AnEndo (a1, a2, a3, a4, a5, a6)
  where
    type EndoOperatesOn (a1, a2, a3, a4, a5, a6) = EndoOperatesOn a1

    anEndo (a1, a2, a3, a4, a5, a6) = mconcat
        [ anEndo a1
        , anEndo a2
        , anEndo a3
        , anEndo a4
        , anEndo a5
        , anEndo a6
        ]

    aDualEndo (a1, a2, a3, a4, a5, a6) = mconcat
        [ aDualEndo a1
        , aDualEndo a2
        , aDualEndo a3
        , aDualEndo a4
        , aDualEndo a5
        , aDualEndo a6
        ]

instance
    ( AnEndo a1
    , AnEndo a2
    , AnEndo a3
    , AnEndo a4
    , AnEndo a5
    , AnEndo a6
    , AnEndo a7
    , EndoOperatesOn a1 ~ EndoOperatesOn a2
    , EndoOperatesOn a1 ~ EndoOperatesOn a3
    , EndoOperatesOn a1 ~ EndoOperatesOn a4
    , EndoOperatesOn a1 ~ EndoOperatesOn a5
    , EndoOperatesOn a1 ~ EndoOperatesOn a6
    , EndoOperatesOn a1 ~ EndoOperatesOn a7
    ) => AnEndo (a1, a2, a3, a4, a5, a6, a7)
  where
    type EndoOperatesOn (a1, a2, a3, a4, a5, a6, a7) = EndoOperatesOn a1

    anEndo (a1, a2, a3, a4, a5, a6, a7) = mconcat
        [ anEndo a1
        , anEndo a2
        , anEndo a3
        , anEndo a4
        , anEndo a5
        , anEndo a6
        , anEndo a7
        ]

    aDualEndo (a1, a2, a3, a4, a5, a6, a7) = mconcat
        [ aDualEndo a1
        , aDualEndo a2
        , aDualEndo a3
        , aDualEndo a4
        , aDualEndo a5
        , aDualEndo a6
        , aDualEndo a7
        ]

instance
    ( AnEndo a1
    , AnEndo a2
    , AnEndo a3
    , AnEndo a4
    , AnEndo a5
    , AnEndo a6
    , AnEndo a7
    , AnEndo a8
    , EndoOperatesOn a1 ~ EndoOperatesOn a2
    , EndoOperatesOn a1 ~ EndoOperatesOn a3
    , EndoOperatesOn a1 ~ EndoOperatesOn a4
    , EndoOperatesOn a1 ~ EndoOperatesOn a5
    , EndoOperatesOn a1 ~ EndoOperatesOn a6
    , EndoOperatesOn a1 ~ EndoOperatesOn a7
    , EndoOperatesOn a1 ~ EndoOperatesOn a8
    ) => AnEndo (a1, a2, a3, a4, a5, a6, a7, a8)
  where
    type EndoOperatesOn (a1, a2, a3, a4, a5, a6, a7, a8) = EndoOperatesOn a1

    anEndo (a1, a2, a3, a4, a5, a6, a7, a8) = mconcat
        [ anEndo a1
        , anEndo a2
        , anEndo a3
        , anEndo a4
        , anEndo a5
        , anEndo a6
        , anEndo a7
        , anEndo a8
        ]

    aDualEndo (a1, a2, a3, a4, a5, a6, a7, a8) = mconcat
        [ aDualEndo a1
        , aDualEndo a2
        , aDualEndo a3
        , aDualEndo a4
        , aDualEndo a5
        , aDualEndo a6
        , aDualEndo a7
        , aDualEndo a8
        ]

instance
    ( AnEndo a1
    , AnEndo a2
    , AnEndo a3
    , AnEndo a4
    , AnEndo a5
    , AnEndo a6
    , AnEndo a7
    , AnEndo a8
    , AnEndo a9
    , EndoOperatesOn a1 ~ EndoOperatesOn a2
    , EndoOperatesOn a1 ~ EndoOperatesOn a3
    , EndoOperatesOn a1 ~ EndoOperatesOn a4
    , EndoOperatesOn a1 ~ EndoOperatesOn a5
    , EndoOperatesOn a1 ~ EndoOperatesOn a6
    , EndoOperatesOn a1 ~ EndoOperatesOn a7
    , EndoOperatesOn a1 ~ EndoOperatesOn a8
    , EndoOperatesOn a1 ~ EndoOperatesOn a9
    ) => AnEndo (a1, a2, a3, a4, a5, a6, a7, a8, a9)
  where
    type EndoOperatesOn (a1, a2, a3, a4, a5, a6, a7, a8, a9) = EndoOperatesOn a1

    anEndo (a1, a2, a3, a4, a5, a6, a7, a8, a9) = mconcat
        [ anEndo a1
        , anEndo a2
        , anEndo a3
        , anEndo a4
        , anEndo a5
        , anEndo a6
        , anEndo a7
        , anEndo a8
        , anEndo a9
        ]

    aDualEndo (a1, a2, a3, a4, a5, a6, a7, a8, a9) = mconcat
        [ aDualEndo a1
        , aDualEndo a2
        , aDualEndo a3
        , aDualEndo a4
        , aDualEndo a5
        , aDualEndo a6
        , aDualEndo a7
        , aDualEndo a8
        , aDualEndo a9
        ]

instance
    ( AnEndo a1
    , AnEndo a2
    , AnEndo a3
    , AnEndo a4
    , AnEndo a5
    , AnEndo a6
    , AnEndo a7
    , AnEndo a8
    , AnEndo a9
    , AnEndo a10
    , EndoOperatesOn a1 ~ EndoOperatesOn a2
    , EndoOperatesOn a1 ~ EndoOperatesOn a3
    , EndoOperatesOn a1 ~ EndoOperatesOn a4
    , EndoOperatesOn a1 ~ EndoOperatesOn a5
    , EndoOperatesOn a1 ~ EndoOperatesOn a6
    , EndoOperatesOn a1 ~ EndoOperatesOn a7
    , EndoOperatesOn a1 ~ EndoOperatesOn a8
    , EndoOperatesOn a1 ~ EndoOperatesOn a9
    , EndoOperatesOn a1 ~ EndoOperatesOn a10
    ) => AnEndo (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10)
  where
    type EndoOperatesOn (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10) = EndoOperatesOn a1

    anEndo (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10) = mconcat
        [ anEndo a1
        , anEndo a2
        , anEndo a3
        , anEndo a4
        , anEndo a5
        , anEndo a6
        , anEndo a7
        , anEndo a8
        , anEndo a9
        , anEndo a10
        ]

    aDualEndo (a1, a2, a3, a4, a5, a6, a7, a8, a9, a10) = mconcat
        [ aDualEndo a1
        , aDualEndo a2
        , aDualEndo a3
        , aDualEndo a4
        , aDualEndo a5
        , aDualEndo a6
        , aDualEndo a7
        , aDualEndo a8
        , aDualEndo a9
        , aDualEndo a10
        ]

-- }}} Instances For Tuples ---------------------------------------------------
-- }}} AnEndo Type Class ------------------------------------------------------

-- {{{ Utility Functions ------------------------------------------------------

-- | Variant of function @('Data.Function.$') :: (a -> b) -> a -> b@ from
-- "Data.Function" module, but with fixity as @(&) :: a -> (a -> b) -> b@
-- function from <http://hackage.haskell.org/package/lens lens package>.
(&$) :: (a -> b) -> a -> b
f &$ a = f a
infixl 1 &$

-- | Variant of function
-- @('Data.Functor.<$>') :: 'Data.Functor.Functor' f => (a -> b) -> a -> b@
-- from "Data.Functor" module, but with fixity as '&$' function.
(<&$>) :: Functor f => (a -> b) -> f a -> f b
(<&$>) = fmap
infixl 1 <&$>

-- | Use 'Endo' (possibly result of 'foldEndo') and use it to create value of
-- different type.
--
-- Examples:
--
-- @
-- 'embedEndoWith' 'Control.Monad.Trans.Writer.Lazy.tell'
--     :: (Monad m, 'AnEndo' e, w ~ 'EndoOperatesOn' e)
--     => e
--     -> 'Control.Monad.Trans.Writer.Lazy.WriterT' ('Endo' w) m ()
--
-- 'embedEndoWith' 'Control.Monad.Trans.State.Lazy.modify'
--     :: (Monad m, 'AnEndo' e, s ~ 'EndoOperatesOn' e)
--     => e
--     -> 'Control.Monad.Trans.State.Lazy.StateT' s m ()
-- @
--
-- See also 'embedDualEndoWith'.
embedEndoWith :: (AnEndo e, EndoOperatesOn e ~ a)
    => (Endo a -> b)
    -- ^ Embedding function.
    -> e -> b
embedEndoWith = (. anEndo)

-- | Dual to 'embedEndoWith', which uses 'aDualEndo' instead of 'anEndo'.
embedDualEndoWith
    :: (AnEndo e, EndoOperatesOn e ~ a)
    => (Dual (Endo a) -> b)
    -- ^ Embedding function.
    -> e -> b
embedDualEndoWith = (. aDualEndo)

-- }}} Utility Functions ------------------------------------------------------

-- $usageExample
--
-- Lets define simple application @Config@ data type as:
--
-- @
-- data Verbosity = Silent | Normal | Verbose | Annoying
--   deriving (Bounded, Data, Enum, Eq, Ord, Show, Typeable)
--
-- data Config = Config
--     { _verbosity :: Verbosity
--     , _outputFile :: FilePath
--     }
--   deriving (Show)
-- @
--
-- Now lets define setters for @_verbosity@ and @_outputFile@:
--
-- @
-- setVerbosity :: Verbosity -> 'Data.Monoid.Endo.E' Config
-- setVerbosity b cfg = cfg{_verbosity = b}
--
-- setOutputFile :: FilePath -> 'Data.Monoid.Endo.E' Config
-- setOutputFile b cfg = cfg{_outputFile = b}
-- @
--
-- Note that 'Data.Monoid.Endo.E' is defined in "Data.Monoid.Endo" module and
-- it looks like:
--
-- @
-- type 'Data.Monoid.Endo.E' a = a -> a
-- @
--
-- Its purpose is to simplify type signatures.
--
-- Now lets get to our first example:
--
-- @
-- example1 :: 'Data.Monoid.Endo.E' Config
-- example1 = 'Data.Monoid.appEndo' '$' 'foldEndo'
--     '&$' setVerbosity Annoying
--     '&$' setOutputFile \"an.out.put\"
-- @
--
-- Above example shows us that it is possible to modify @Config@ as if it was a
-- monoid, but without actually having to state it as such. In practice it is
-- not always possible to define it as 'Monoid' or at least a @Semigroup@. What
-- usually works are endomorphisms, like in this example.
--
-- Now, 'System.IO.FilePath' has one pathological case, and that is \"\". There
-- is a lot of ways to handle it. Here we will concentrate only few basic
-- techniques to illustrate versatility of our approach.
--
-- @
-- -- | Trying to set output file to \"\" will result in keeping original
-- -- value.
-- setOutputFile2 :: FilePath -> 'Data.Monoid.Endo.E' Config
-- setOutputFile2 \"\" = id
-- setOutputFile2 fp = setOutputFile fp
--
-- example2 :: 'Data.Monoid.Endo.E' Config
-- example2 = 'Data.Monoid.appEndo' $ 'foldEndo'
--     '&$' setVerbosity Annoying
--     '&$' setOutputFile2 \"an.out.put\"
-- @
--
-- Same as above, but exploits @instance 'AnEndo' a => 'AnEndo' 'Maybe' a@:
--
-- @
-- setOutputFile3 :: FilePath -> Maybe ('Data.Monoid.Endo.E' Config)
-- setOutputFile3 "" = Nothing
-- setOutputFile3 fp = Just $ setOutputFile fp
--
-- example3 :: 'Data.Monoid.Endo.E' Config
-- example3 = 'Data.Monoid.appEndo' $ 'foldEndo'
--     '&$' setVerbosity Annoying
--     '&$' setOutputFile3 \"an.out.put\"
-- @
--
-- Following example uses common pattern of using 'Either' as error reporting
-- monad. This approach can be easily modified for arbitrary error reporting
-- monad.
--
-- @
-- setOutputFile4 :: FilePath -> Either String ('Data.Monoid.Endo.E' Config)
-- setOutputFile4 "" = Left \"Output file: Empty file path.\"
-- setOutputFile4 fp = Right $ setOutputFile fp
--
-- example4 :: Either String ('Data.Monoid.Endo.E' Config)
-- example4 = 'Data.Monoid.appEndo' '<&$>' 'foldEndo'
--     'Control.Applicative.<*>' 'pure' (setVerbosity Annoying)
--     'Control.Applicative.<*>' setOutputFile4 \"an.out.put\"
-- @
--
-- Notice, that above example uses applicative style. Normally when using this
-- style, for setting record values, one needs to keep in sync order of
-- constructor arguments and order of operations. Using 'foldEndo' (and its
-- dual 'dualFoldEndo') doesn't have this restriction.
--
-- Instead of setter functions one may want to use lenses (in terms of
-- <http://hackage.haskell.org/package/lens lens package>):
--
-- @
-- verbosity :: Lens' Config Verbosity
-- verbosity =
--     _verbosity 'Data.Function.Between.~@@^>' \\s b -> s{_verbosity = b}
--
-- outputFile :: Lens' Config FilePath
-- outputFile =
--     _outputFile 'Data.Function.Between.~@@^>' \\s b -> s{_outputFile = b}
-- @
--
-- Now setting values of @Config@ would look like:
--
-- @
-- example5 :: 'Data.Monoid.Endo.E' Config
-- example5 = 'Data.Monoid.appEndo' $ 'foldEndo'
--     '&$' verbosity  .~ Annoying
--     '&$' outputFile .~ \"an.out.put\"
-- @
--
-- Probably one of the most interesting things that can be done with this
-- module is following:
--
-- @
-- instance 'AnEndo' Verbosity where
--     type 'EndoOperatesOn' Verbosity = Config
--     'anEndo' = Endo . set verbosity
--
-- newtype OutputFile = OutputFile FilePath
--
-- instance 'AnEndo' OutputFile where
--     type 'EndoOperatesOn' OutputFile = Config
--     'anEndo' (OutputFile fp) = 'Endo' $ outputFile .~ fp
--
-- example6 :: 'Data.Monoid.Endo.E' Config
-- example6 = 'Data.Monoid.appEndo' $ 'foldEndo'
--     '&$' Annoying
--     '&$' OutputFile \"an.out.put\"
-- @

-- $optparseApplicativeExample
--
-- This is a more complex example that defines parser for
-- <http://hackage.haskell.org/package/optparse-applicative optparse-applicative>
-- built on top of some of the above definitions:
--
-- @
-- options :: Parser Config
-- options = 'Control.Monad.Trans.Identity.runIdentityT' $ 'Control.Monad.Endo.runEndo' defaultConfig \<$\> options'
--   where
--     -- All this IdentityT clutter is here to avoid orphan instances.
--     options' :: 'IdentityT' Parser ('Endo' Config)
--     options' = 'foldEndo'
--         \<*\> outputOption     -- :: IdentityT Parser (Maybe (E Config))
--         \<*\> verbosityOption  -- :: IdentityT Parser (Maybe (E Config))
--         \<*\> annoyingFlag     -- :: IdentityT Parser (E Config)
--         \<*\> silentFlag       -- :: IdentityT Parser (E Config)
--         \<*\> verboseFlag      -- :: IdentityT Parser (E Config)
--
--     defaultConfig :: Config
--     defaultConfig = Config Normal \"\"
--
-- main :: IO ()
-- main = execParser (info options fullDesc) \>\>= print
-- @
--
-- Example of running above @main@ function:
--
-- >>> :main -o an.out.put --annoying
-- Config {_verbosity = Annoying, _outputFile = "an.out.put"}
--
-- Parsers for individual options and flags are wrapped in 'IdentityT', because
-- there is no following instance:
--
-- @
-- instance 'FoldEndoArgs' r => 'FoldEndoArgs' (Parser r)
-- @
--
-- But there is:
--
-- @
-- instance ('Applicative' f, 'FoldEndoArgs' r) => 'FoldEndoArgs' ('IdentityT' f r)
-- @
--
-- Functions used by the above code example:
--
-- @
-- outputOption :: 'IdentityT' Parser (Maybe ('Data.Monoid.Endo.E' Config))
-- outputOption =
--     IdentityT . optional . option (set outputFile \<$\> parseFilePath)
--     $ short \'o\' \<\> long \"output\" \<\> metavar \"FILE\"
--         \<\> help \"Store output in to a FILE.\"
--   where
--     parseFilePath = eitherReader $ \\s ->
--         if null s
--             then Left \"Option argument can not be empty file path.\"
--             else Right s
--
-- verbosityOption :: 'IdentityT' Parser (Maybe ('Data.Monoid.Endo.E' Config))
-- verbosityOption =
--     'IdentityT' . optional . option (set verbosity \<$\> parseVerbosity)
--     $ long \"verbosity\" \<\> metavar \"LEVEL\" \<\> help \"Set verbosity to LEVEL.\"
--   where
--     verbosityToStr = map toLower . Data.showConstr . Data.toConstr
--     verbosityIntValues = [(show $ fromEnum v, v) | v <- [Silent .. Annoying]]
--     verbosityStrValues =
--         ("default", Normal) : [(verbosityToStr v, v) | v <- [Silent .. Annoying]]
--
--     parseVerbosityError = unwords
--         [ "Verbosity can be only number from interval"
--         , show $ map fromEnum [minBound, maxBound :: Verbosity]
--         , "or one of the following:"
--         , concat . intersperse ", " $ map fst verbosityStrValues
--         ]
--
--     parseVerbosity = eitherReader $ \s ->
--         case lookup s $ verbosityIntValues ++ verbosityStrValues of
--             Just v  -> Right v
--             Nothing -> Left parseVerbosityError
--
-- annoyingFlag :: 'IdentityT' Parser ('Data.Monoid.Endo.E' Config)
-- annoyingFlag = 'IdentityT' . flag id (verbosity .~ Annoying)
--     $ long \"annoying\" \<\> help \"Set verbosity to maximum.\"
--
-- silentFlag :: 'IdentityT' Parser ('Data.Monoid.Endo.E' Config)
-- silentFlag = 'IdentityT' . flag id (verbosity .~ Silent)
--     $ short 's' \<\> long "silent" \<\> help \"Set verbosity to minimum.\"
--
-- verboseFlag :: 'IdentityT' Parser ('Data.Monoid.Endo.E' Config)
-- verboseFlag = 'IdentityT' . flag id (verbosity .~ Verbose)
--     $ short 'v' \<\> long \"verbose\" \<\> help \"Be verbose.\"
-- @
