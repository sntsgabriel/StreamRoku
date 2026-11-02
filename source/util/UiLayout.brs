' Fit a native widget's full unscaled extent inside a viewport, including side controls.
function FitWidgetRect(rect as dynamic, width as float, height as float, maxScale = 0.7 as float) as dynamic
    if rect = invalid or width <= 0 or height <= 0 then return invalid
    if rect.width = invalid or rect.height = invalid then return invalid
    if rect.width <= 0 or rect.height <= 0 then return invalid
    factor = width / rect.width
    if height / rect.height < factor then factor = height / rect.height
    if maxScale < factor then factor = maxScale
    if factor <= 0 then return invalid
    x = 0
    y = 0
    if rect.x <> invalid then x = rect.x
    if rect.y <> invalid then y = rect.y
    return { scale: [factor, factor], translation: [-x * factor, -y * factor] }
end function
