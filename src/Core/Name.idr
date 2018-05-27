module Core.Name

mutual
  public export
  data GenName = Nested Name Name -- a name in a nested scope
               | CaseBlock Name Int -- autogenerated name for a case block function
               | WithBlock Name Int -- autogenerated name for a with block function

  public export
  data Name = UN String -- user given name
            | MN String Int -- machine generated name
            | NS (List String) Name -- a name in a hierarchical namespace 
                  -- namespaces are in reverse order (innermost name first)
            | HN String Int -- machine generated metavariable name
            | PV String -- implicitly bound pattern variable name
            | GN GenName -- various kinds of generated names

gnameTag : GenName -> Int
gnameTag (Nested _ _) = 0
gnameTag (CaseBlock _ _) = 1
gnameTag (WithBlock _ _) = 2

nameTag : Name -> Int
nameTag (UN _) = 0
nameTag (MN _ _) = 1
nameTag (NS _ _) = 2
nameTag (HN _ _) = 3
nameTag (PV _) = 4
nameTag (GN _) = 5

mutual
  export
  gnameRoot : GenName -> String
  gnameRoot (Nested outer inner) = nameRoot inner
  gnameRoot (CaseBlock outer count) = nameRoot outer
  gnameRoot (WithBlock outer count) = nameRoot outer

  export
  nameRoot : Name -> String
  nameRoot (UN x) = x
  nameRoot (MN x y) = x
  nameRoot (NS xs x) = nameRoot x
  nameRoot (HN x y) = x
  nameRoot (PV x) = x
  nameRoot (GN x) = gnameRoot x

  export
  userNameRoot : Name -> Maybe String
  userNameRoot (UN x) = Just x
  userNameRoot (MN x y) = Nothing
  userNameRoot (NS xs x) = userNameRoot x
  userNameRoot (HN x y) = Nothing
  userNameRoot (PV x) = Nothing
  userNameRoot (GN x) = Nothing

export
isUserName : Name -> Bool
isUserName (UN _) = True
isUserName (NS _ n) = isUserName n
isUserName _ = False

export
dropNS : Name -> Name
dropNS (NS _ n) = n
dropNS n = n

export
showSep : String -> List String -> String
showSep sep [] = ""
showSep sep [x] = x
showSep sep (x :: xs) = x ++ sep ++ showSep sep xs

mutual
  export
  Show GenName where
    show (Nested outer inner) = show outer ++ ":" ++ show inner
    show (CaseBlock outer i) = "case-block-" ++ show i ++ "-in-" ++ show outer
    show (WithBlock outer i) = "with-block-" ++ show i ++ "-in-" ++ show outer

  export
  Show Name where
    show (UN str) = str
    show (MN str int) = "{" ++ str ++ ":" ++ show int ++ "}"
    show (NS ns n) = showSep "." (reverse ns) ++ "." ++ show n
    show (HN str int) = "?" ++ str ++ "_" ++ show int
    show (PV str) = "{P:" ++ str ++ "}"
    show (GN gn) = show gn

mutual
  export
  Eq GenName where
    (==) (Nested x1 x2) (Nested y1 y2) = x1 == y1 && x2 == y2
    (==) (CaseBlock x1 x2) (CaseBlock y1 y2) = x1 == y1 && x2 == y2
    (==) (WithBlock x1 x2) (WithBlock y1 y2) = x1 == y1 && x2 == y2
    (==) _ _ = False

  export
  Eq Name where
    (==) (UN x) (UN y) = x == y
    (==) (MN x y) (MN x' y') = x == x' && y == y'
    (==) (NS xs x) (NS xs' x') = xs == xs' && x == x'
    (==) (HN x y) (HN x' y') = x == x' && y == y'
    (==) (PV x) (PV y) = x == y
    (==) (GN x) (GN y) = x == y
    (==) _ _ = False

-- There's no way I'm maintaining a DecEq instance for this without
-- deriving it automatically... this is boring enough...
-- Maybe there should be a type class for these - things which are
-- weaker than DecEq but nevertheless useful - at least until I work out
-- how to get deriving DecEq to work (and if we want to use that feature
-- here in any case... might be best to avoid extensions if there really
-- is a self hosting goal)
mutual
  export
  gnameEq : (x : GenName) -> (y : GenName) -> Maybe (x = y)
  gnameEq (Nested x1 y1) (Nested x2 y2) with (nameEq x1 x2)
    gnameEq (Nested x1 y1) (Nested x2 y2) | Nothing = Nothing
    gnameEq (Nested x1 y1) (Nested x2 y2) | (Just x) with (nameEq y1 y2)
      gnameEq (Nested x1 y1) (Nested x2 y2) | (Just x) | Nothing = Nothing
      gnameEq (Nested x2 y2) (Nested x2 y2) | (Just Refl) | (Just Refl) = Just Refl
  gnameEq (CaseBlock x1 y1) (CaseBlock x2 y2) with (nameEq x1 x2)
    gnameEq (CaseBlock x1 y1) (CaseBlock x2 y2) | Nothing = Nothing
    gnameEq (CaseBlock x1 y1) (CaseBlock x2 y2) | (Just x) with (decEq y1 y2)
      gnameEq (CaseBlock x1 y1) (CaseBlock x2 y2) | (Just x) | (No _) = Nothing
      gnameEq (CaseBlock x2 y2) (CaseBlock x2 y2) | (Just Refl) | (Yes Refl) = Just Refl
  gnameEq (WithBlock x1 y1) (WithBlock x2 y2) with (nameEq x1 x2)
    gnameEq (WithBlock x1 y1) (WithBlock x2 y2) | Nothing = Nothing
    gnameEq (WithBlock x1 y1) (WithBlock x2 y2) | (Just x) with (decEq y1 y2)
      gnameEq (WithBlock x1 y1) (WithBlock x2 y2) | (Just x) | (No _) = Nothing
      gnameEq (WithBlock x2 y2) (WithBlock x2 y2) | (Just Refl) | (Yes Refl) = Just Refl
  gnameEq _ _ = Nothing

  export
  nameEq : (x : Name) -> (y : Name) -> Maybe (x = y)
  nameEq (UN x) (UN y) with (decEq x y)
    nameEq (UN y) (UN y) | (Yes Refl) = Just Refl
    nameEq (UN x) (UN y) | (No contra) = Nothing
  nameEq (MN x t) (MN x' t') with (decEq x x')
    nameEq (MN x t) (MN x t') | (Yes Refl) with (decEq t t')
      nameEq (MN x t) (MN x t) | (Yes Refl) | (Yes Refl) = Just Refl
      nameEq (MN x t) (MN x t') | (Yes Refl) | (No contra) = Nothing
    nameEq (MN x t) (MN x' t') | (No contra) = Nothing
  nameEq (NS xs x) (NS ys y) with (decEq xs ys)
    nameEq (NS ys x) (NS ys y) | (Yes Refl) with (nameEq x y)
      nameEq (NS ys x) (NS ys y) | (Yes Refl) | Nothing = Nothing
      nameEq (NS ys y) (NS ys y) | (Yes Refl) | (Just Refl) = Just Refl
    nameEq (NS xs x) (NS ys y) | (No contra) = Nothing
  nameEq (HN x t) (HN x' t') with (decEq x x')
    nameEq (HN x t) (HN x t') | (Yes Refl) with (decEq t t')
      nameEq (HN x t) (HN x t) | (Yes Refl) | (Yes Refl) = Just Refl
      nameEq (HN x t) (HN x t') | (Yes Refl) | (No contra) = Nothing
    nameEq (HN x t) (HN x' t') | (No contra) = Nothing
  nameEq (PV x) (PV y) with (decEq x y)
    nameEq (PV y) (PV y) | (Yes Refl) = Just Refl
    nameEq (PV x) (PV y) | (No contra) = Nothing
  nameEq (GN x) (GN y) with (gnameEq x y)
    nameEq (GN x) (GN y) | Nothing = Nothing
    nameEq (GN x) (GN x) | (Just Refl) = Just Refl
  nameEq _ _ = Nothing

mutual
  export
  Ord GenName where
    compare (Nested x1 x2) (Nested y1 y2) 
        = case compare x1 y1 of
               EQ => compare x2 y2
               t => t
    compare (CaseBlock x1 x2) (CaseBlock y1 y2) 
        = case compare x1 y1 of
               EQ => compare x2 y2
               t => t
    compare (WithBlock x1 x2) (WithBlock y1 y2) 
        = case compare x1 y1 of
               EQ => compare x2 y2
               t => t
    compare x y = compare (gnameTag x) (gnameTag y)

  export
  Ord Name where
    compare (UN x) (UN y) = compare x y
    compare (MN x y) (MN x' y') 
        = case compare x x' of
               EQ => compare y y'
               t => t
    compare (NS x y) (NS x' y') 
        = case compare x x' of
               EQ => compare y y'
               t => t
    compare (HN x y) (HN x' y') 
        = case compare x x' of
               EQ => compare y y'
               t => t
    compare (PV x) (PV y) = compare x y
    compare (GN x) (GN y) = compare x y

    compare x y = compare (nameTag x) (nameTag y)

hashString : String -> Int
hashString "" = 1
hashString xs 
    = assert_total $
        cast (prim__strHead xs) + hashString (prim__strTail xs) * 31

export
hashName : Name -> Int
hashName x = hashString (show x)

