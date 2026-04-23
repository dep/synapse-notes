import { useEffect, useState } from 'react'

export function useWindowWidth(): number {
  const [width, setWidth] = useState(() =>
    typeof window === 'undefined' ? 1920 : window.innerWidth,
  )

  useEffect(() => {
    const onResize = () => setWidth(window.innerWidth)
    window.addEventListener('resize', onResize)
    return () => window.removeEventListener('resize', onResize)
  }, [])

  return width
}
